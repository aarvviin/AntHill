import SwiftUI

let antColor = Color(red: 0.15, green: 0.08, blue: 0.04)

struct AntView: View {
    @ObservedObject var c: Colony
    var tapHole: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                _ = c.frame
                drawHole(ctx)
                for e in c.expeditions {
                    for a in e.ants { drawAnt(ctx, a) }
                    if e.showsImage { drawLoad(ctx, e) }
                }
                for s in c.scouts { drawAnt(ctx, s.ant) }
            }
            Circle().fill(Color.white.opacity(0.001))
                .frame(width: 64, height: 64)
                .position(c.hole)
                .onTapGesture(perform: tapHole)
        }
    }

    func drawHole(_ ctx: GraphicsContext) {
        let h = c.hole
        let mound = CGRect(x: h.x - 30, y: h.y - 13, width: 60, height: 26)
        ctx.fill(Path(ellipseIn: mound.offsetBy(dx: 2, dy: 3)), with: .color(.black.opacity(0.22)))
        ctx.fill(Path(ellipseIn: mound), with: .radialGradient(
            Gradient(colors: [Color(red: 0.62, green: 0.42, blue: 0.22), Color(red: 0.38, green: 0.24, blue: 0.11)]),
            center: CGPoint(x: h.x - 6, y: h.y - 6), startRadius: 2, endRadius: 34))
        // crumbs
        for (dx, dy, r) in [(-24.0, 9.0, 2.2), (26, 7, 1.8), (-33, -2, 1.5), (31, -4, 2.0), (-14, 14, 1.4), (17, 13, 1.6), (6, -14, 1.3)] {
            ctx.fill(Path(ellipseIn: CGRect(x: h.x + dx - r, y: h.y + dy - r, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 0.45, green: 0.29, blue: 0.14)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: h.x - 10, y: h.y - 5, width: 20, height: 9)), with: .color(Color(red: 0.08, green: 0.04, blue: 0.02)))
        if c.stored > 0 {
            let text = ctx.resolve(Text("\(c.stored)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white))
            let sz = text.measure(in: CGSize(width: 100, height: 20))
            let pill = CGRect(x: h.x + 20, y: h.y - 24, width: sz.width + 10, height: 15)
            ctx.fill(Path(roundedRect: pill, cornerRadius: 7.5), with: .color(Color(red: 0.38, green: 0.24, blue: 0.11)))
            ctx.draw(text, at: CGPoint(x: pill.midX, y: pill.midY))
        }
    }

    func drawAnt(_ ctx: GraphicsContext, _ a: Ant) {
        guard a.scale > 0.01 else { return }
        var g = ctx
        g.translateBy(x: a.p.x, y: a.p.y)
        g.rotate(by: .radians(Double(a.h)))
        g.scaleBy(x: a.scale * 1.2, y: a.scale * 1.2)
        // legs, tripod gait: front and back of one side move with the middle of the other
        var legs = Path()
        for (i, x) in [CGFloat(1.5), 0, -1.5].enumerated() {
            for side in [CGFloat(-1), 1] {
                let phase = a.gait + (i == 1 ? .pi : 0) + (side > 0 ? .pi : 0)
                let swing = sin(phase) * 2.2
                let splay = (CGFloat(i) - 1) * -1.6
                let knee = CGPoint(x: x + swing * 0.5 + splay, y: side * 3.2)
                legs.move(to: CGPoint(x: x, y: 0))
                legs.addLine(to: knee)
                legs.addLine(to: CGPoint(x: knee.x + swing + splay, y: side * 5.6))
            }
        }
        g.stroke(legs, with: .color(antColor), lineWidth: 0.9)
        var feelers = Path()
        for side in [CGFloat(-1), 1] {
            feelers.move(to: CGPoint(x: 5.8, y: side * 0.8))
            feelers.addLine(to: CGPoint(x: 8.4, y: side * 2.6))
            feelers.addLine(to: CGPoint(x: 10.6, y: side * (2.0 + sin(a.gait * 1.3 + side) * 0.6)))
        }
        g.stroke(feelers, with: .color(antColor), lineWidth: 0.7)
        g.fill(Path(ellipseIn: CGRect(x: -9.5, y: -2.9, width: 7.8, height: 5.8)), with: .color(antColor))
        g.fill(Path(ellipseIn: CGRect(x: -2.2, y: -1.6, width: 4.8, height: 3.2)), with: .color(antColor))
        g.fill(Path(ellipseIn: CGRect(x: 2.6, y: -2.1, width: 4.2, height: 4.2)), with: .color(antColor))
        g.fill(Path(ellipseIn: CGRect(x: -8, y: -2.1, width: 2.6, height: 1.4)), with: .color(.white.opacity(0.28)))
    }

    func drawLoad(_ ctx: GraphicsContext, _ e: Expedition) {
        let s = CGSize(width: e.size.width * e.imgScale, height: e.size.height * e.imgScale)
        guard s.width > 0.5 else { return }
        let d = hypot(c.hole.x - e.center.x, c.hole.y - e.center.y)
        let perp = d > 0 ? CGPoint(x: -(c.hole.y - e.center.y) / d * e.sway, y: (c.hole.x - e.center.x) / d * e.sway) : .zero
        let p = e.center + perp
        let raise = e.lift * 5
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - s.width * 0.45 + 3, y: p.y - s.height * 0.35 + 5, width: s.width * 0.9, height: s.height * 0.75)),
                 with: .color(.black.opacity(0.18 * e.lift)))
        var g = ctx
        g.translateBy(x: p.x, y: p.y - raise)
        g.rotate(by: .radians(Double(e.tilt)))
        g.fill(Path(roundedRect: CGRect(x: -s.width / 2 - 2, y: -s.height / 2 - 2, width: s.width + 4, height: s.height + 4), cornerRadius: 3),
               with: .color(.white))
        g.draw(Image(nsImage: e.image), in: CGRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height))
    }
}
