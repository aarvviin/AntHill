import AppKit

// All coordinates are top-left origin points on the main screen, the same space Finder uses for desktop positions.

struct Ant {
    var p: CGPoint
    var h: CGFloat = 0          // heading in radians, y points down
    var gait: CGFloat = 0       // leg cycle
    var scale: CGFloat = 0
    var delay: Double = 0       // seconds before it climbs out of the hole
    var arrived = false
    var spook: Double = 0       // seconds left running away from the cursor
}

func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }

func turn(_ h: CGFloat, toward want: CGFloat, by maxStep: CGFloat) -> CGFloat {
    var d = (want - h).truncatingRemainder(dividingBy: 2 * .pi)
    if d > .pi { d -= 2 * .pi }
    if d < -.pi { d += 2 * .pi }
    return h + max(-maxStep, min(maxStep, d))
}

final class Expedition {
    enum Phase { case outbound, lifting, carrying, entering, done }
    var phase = Phase.outbound
    var t: Double = 0
    let url: URL
    let target: CGPoint
    let image: NSImage
    let size: CGSize
    var center: CGPoint
    var heading: CGFloat
    var ants: [Ant] = []
    var slots: [CGPoint] = []
    var picked = false
    var carrying = false
    var popped = false
    var lift: CGFloat = 0
    var imgScale: CGFloat = 1
    var sway: CGFloat = 0
    var tilt: CGFloat = 0

    var showsImage: Bool { carrying && phase != .outbound }

    init(url: URL, target: CGPoint, image: NSImage, hole: CGPoint) {
        self.url = url
        self.target = target
        self.image = image
        center = target
        heading = atan2(hole.y - target.y, hole.x - target.x)
        let box: CGFloat = 58
        let a = image.size.height > 0 ? image.size.width / image.size.height : 1
        size = a >= 1 ? CGSize(width: box, height: box / a) : CGSize(width: box * a, height: box)
        let hw = size.width / 2 + 1, hh = size.height / 2 + 1
        // six carriers around the edges, poking out from under the picture
        slots = [CGPoint(x: hw, y: -hh * 0.45), CGPoint(x: hw, y: hh * 0.45),
                 CGPoint(x: 0, y: -hh), CGPoint(x: 0, y: hh),
                 CGPoint(x: -hw, y: -hh * 0.45), CGPoint(x: -hw, y: hh * 0.45)]
        let out = atan2(target.y - hole.y, target.x - hole.x)
        for i in 0..<slots.count {
            ants.append(Ant(p: hole, h: out, delay: Double(i) * 0.35))
        }
    }
}

struct Scout {
    var ant: Ant
    var goal: CGPoint
    var phase = 0
    var t: Double = 0
    var linger: Double
    var seed: CGFloat
    var done = false
}

final class Colony: ObservableObject {
    @Published var frame = 0
    @Published var hole = CGPoint(x: 200, y: 200)
    @Published var stored = 0
    var bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    var mouse = CGPoint(x: -999, y: -999)
    var expeditions: [Expedition] = []
    var scouts: [Scout] = []
    var paused = false
    var time: Double = 0
    var nextScout: Double = 6

    // moves the file into the anthill; false if it vanished meanwhile
    var pickup: (URL) -> Bool = { _ in false }
    var delivered: () -> Void = {}

    var active: Bool { !expeditions.isEmpty || !scouts.isEmpty }

    func send(url: URL, target: CGPoint, image: NSImage) {
        expeditions.append(Expedition(url: url, target: target, image: image, hole: hole))
    }

    func step(_ dt: Double) {
        time += dt
        if !paused, expeditions.isEmpty, time > nextScout {
            for _ in 0..<Int.random(in: 1...2) { spawnScout() }
            nextScout = time + .random(in: 15...35)
        }
        guard active else { return }
        for e in expeditions { update(e, CGFloat(dt)) }
        expeditions.removeAll { $0.phase == .done }
        for i in scouts.indices { update(&scouts[i], CGFloat(dt)) }
        scouts.removeAll { $0.done }
        frame &+= 1
    }

    // steers an ant toward a goal with a wiggle; scared ants run away from the cursor. true on arrival.
    private func walk(_ a: inout Ant, to goal: CGPoint, speed: CGFloat, dt: CGFloat, wobble: CGFloat, seed: CGFloat) -> Bool {
        let mx = a.p.x - mouse.x, my = a.p.y - mouse.y
        if hypot(mx, my) < 55 { a.spook = 0.7 }
        if a.spook > 0 {
            a.spook -= Double(dt)
            a.h = turn(a.h, toward: atan2(my, mx), by: 14 * dt)
            let step = speed * 3 * dt
            a.p.x = max(bounds.minX + 4, min(bounds.maxX - 4, a.p.x + cos(a.h) * step))
            a.p.y = max(bounds.minY + 4, min(bounds.maxY - 4, a.p.y + sin(a.h) * step))
            a.gait += step * 0.9
            return false
        }
        let dx = goal.x - a.p.x, dy = goal.y - a.p.y
        let d = hypot(dx, dy)
        if d < 1.5 { a.p = goal; return true }
        let step = min(d, speed * dt)
        if d < 12 {
            a.p.x += dx / d * step
            a.p.y += dy / d * step
        } else {
            let want = atan2(dy, dx) + sin(CGFloat(time) * 5 + seed) * wobble
            a.h = turn(a.h, toward: want, by: 9 * dt)
            a.p.x += cos(a.h) * step
            a.p.y += sin(a.h) * step
        }
        a.gait += step * 0.9
        return false
    }

    private func update(_ e: Expedition, _ dt: CGFloat) {
        e.t += Double(dt)
        switch e.phase {
        case .outbound:
            var all = true
            for i in e.ants.indices {
                if e.t < e.ants[i].delay { all = false; continue }
                e.ants[i].scale = min(1, CGFloat((e.t - e.ants[i].delay) / 0.3))
                if !e.ants[i].arrived {
                    e.ants[i].arrived = walk(&e.ants[i], to: e.target + e.slots[i], speed: 75, dt: dt, wobble: 0.5, seed: CGFloat(i))
                }
                if e.ants[i].arrived {
                    e.ants[i].h = turn(e.ants[i].h, toward: e.heading, by: 6 * dt)
                } else {
                    all = false
                }
            }
            if all { e.phase = .lifting; e.t = 0 }

        case .lifting:
            if !e.picked && e.t > 0.3 {
                e.picked = true
                e.carrying = pickup(e.url)
            }
            e.lift = CGFloat(min(1, e.t / 0.6))
            for i in e.ants.indices { e.ants[i].gait += dt * 6 }
            if e.t > 0.8 { e.phase = .carrying; e.t = 0 }

        case .carrying:
            let dx = hole.x - e.center.x, dy = hole.y - e.center.y
            let d = hypot(dx, dy)
            if d < 2 { e.phase = .entering; e.t = 0; break }
            let step = min(d, (e.carrying ? 38 : 70) * dt)
            e.heading = atan2(dy, dx)
            e.center.x += dx / d * step
            e.center.y += dy / d * step
            e.sway = sin(CGFloat(time) * 3.1) * 2.5
            e.tilt = sin(CGFloat(time) * 2.3) * 0.07
            let perp = CGPoint(x: -dy / d * e.sway, y: dx / d * e.sway)
            for i in e.ants.indices {
                e.ants[i].p = e.center + e.slots[i] + perp
                e.ants[i].h = turn(e.ants[i].h, toward: e.heading + sin(CGFloat(time) * 7 + CGFloat(i)) * 0.25, by: 8 * dt)
                e.ants[i].gait += step * 0.9
            }

        case .entering:
            e.imgScale = max(0, 1 - CGFloat(e.t / 0.45))
            if !e.popped && e.t > 0.35 {
                e.popped = true
                if e.carrying { NSSound(named: "Pop")?.play(); delivered() }
            }
            for i in e.ants.indices {
                let start = 0.35 + Double(i) * 0.12
                guard e.t > start else { continue }
                let k = CGFloat(min(1, (e.t - start) / 0.25))
                e.ants[i].scale = 1 - k
                e.ants[i].p.x += (hole.x - e.ants[i].p.x) * min(1, dt * 8)
                e.ants[i].p.y += (hole.y - e.ants[i].p.y) * min(1, dt * 8)
                e.ants[i].gait += dt * 12
            }
            if e.t > 0.35 + Double(e.ants.count) * 0.12 + 0.3 { e.phase = .done }

        case .done:
            break
        }
    }

    private func spawnScout() {
        let a = CGFloat.random(in: 0...(2 * .pi)), r = CGFloat.random(in: 50...150)
        var goal = CGPoint(x: hole.x + cos(a) * r, y: hole.y + sin(a) * r * 0.7)
        goal.x = max(bounds.minX + 20, min(bounds.maxX - 20, goal.x))
        goal.y = max(bounds.minY + 20, min(bounds.maxY - 20, goal.y))
        scouts.append(Scout(ant: Ant(p: hole, h: atan2(goal.y - hole.y, goal.x - hole.x)),
                            goal: goal, linger: .random(in: 1.2...3.5), seed: .random(in: 0...10)))
    }

    private func update(_ s: inout Scout, _ dt: CGFloat) {
        s.t += Double(dt)
        switch s.phase {
        case 0:
            s.ant.scale = min(1, CGFloat(s.t / 0.3))
            if walk(&s.ant, to: s.goal, speed: 45, dt: dt, wobble: 0.7, seed: s.seed) { s.phase = 1; s.t = 0 }
        case 1:
            // look around, wave antennae
            s.ant.h += sin(CGFloat(time) * 2 + s.seed) * dt * 2.5
            s.ant.gait += dt * 2
            if s.t > s.linger { s.phase = 2; s.t = 0 }
        case 2:
            if walk(&s.ant, to: hole, speed: 55, dt: dt, wobble: 0.6, seed: s.seed) { s.phase = 3; s.t = 0 }
        default:
            s.ant.scale = max(0, 1 - CGFloat(s.t / 0.3))
            if s.t > 0.3 { s.done = true }
        }
    }
}
