import AppKit
import SwiftUI

// A transparent window just above the desktop icons and below every other window.
// It only takes clicks on the anthill itself.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let colony = Colony()
    var window: NSWindow!
    var screen: NSScreen!
    var last = CACurrentMediaTime()
    var inFlight: Set<String> = []
    var sendNow = false
    let defaults = UserDefaults.standard

    var grace: TimeInterval {
        get { defaults.object(forKey: "grace") as? TimeInterval ?? 120 }
        set { defaults.set(newValue, forKey: "grace") }
    }
    var spared: Set<String> {
        get { Set(defaults.stringArray(forKey: "spared") ?? []) }
        set { defaults.set(Array(newValue), forKey: "spared") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: AntView(c: colony) { [weak self] in self?.showMenu() })
        colony.paused = defaults.bool(forKey: "paused")
        colony.pickup = { Desk.haul($0) }
        colony.delivered = { [weak self] in self?.colony.stored = Desk.storedCount }
        colony.stored = Desk.storedCount
        place()
        window.orderFrontRegardless()
        NotificationCenter.default.addObserver(self, selector: #selector(place),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let tick = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tick, forMode: .common)
        let scan = Timer(timeInterval: 4, repeats: true) { [weak self] _ in self?.scan() }
        RunLoop.main.add(scan, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.scan() }
    }

    @objc func place() {
        screen = NSScreen.screens[0]
        let f = screen.frame, vf = screen.visibleFrame
        window.setFrame(f, display: true)
        colony.bounds = CGRect(origin: .zero, size: f.size)
        colony.hole = CGPoint(x: vf.maxX - f.minX - 80, y: f.maxY - vf.minY - 60)
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.05, now - last)
        last = now
        let f = screen.frame
        let m = NSEvent.mouseLocation
        let p = CGPoint(x: m.x - f.minX, y: f.maxY - m.y)
        colony.mouse = p
        colony.step(dt)
        let overHole = hypot(p.x - colony.hole.x, p.y - colony.hole.y) < 32
        if window.ignoresMouseEvents == overHole { window.ignoresMouseEvents = !overHole }
    }

    // up to two crews out at a time
    func scan() {
        guard !colony.paused else { return }
        let force = sendNow
        sendNow = false
        for u in Desk.screenshots(olderThan: force ? 0 : grace, sparing: spared) {
            guard colony.expeditions.count < 2 else { break }
            let name = u.lastPathComponent
            guard !inFlight.contains(name) else { continue }
            inFlight.insert(name)
            let target = Desk.position(of: name) ?? CGPoint(
                x: colony.bounds.width - .random(in: 60...260), y: .random(in: 60...(colony.bounds.height / 2)))
            colony.send(url: u, target: target, image: Desk.thumbnail(u))
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { self.inFlight.remove(name) }
        }
    }

    // MARK: menu

    func showMenu() {
        let menu = NSMenu()
        let n = Desk.storedCount
        let head = NSMenuItem(title: n == 0 ? "🐜 The anthill is empty" : "🐜 \(n) screenshot\(n == 1 ? "" : "s") in the anthill", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())
        add(menu, "Send the ants now", #selector(sendAntsNow))
        add(menu, "Open the anthill", #selector(openAnthill))
        add(menu, "Bring them all back", #selector(bringBack)).isEnabled = n > 0
        menu.addItem(.separator())
        let graceItem = NSMenuItem(title: "Leave new screenshots alone for", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (title, secs) in [("1 minute", 60.0), ("2 minutes", 120), ("10 minutes", 600), ("1 hour", 3600), ("1 day", 86400)] {
            let it = add(sub, title, #selector(setGrace(_:)))
            it.representedObject = secs
            it.state = grace == secs ? .on : .off
        }
        graceItem.submenu = sub
        menu.addItem(graceItem)
        add(menu, colony.paused ? "Wake the ants" : "Let the ants nap", #selector(togglePause))
        menu.addItem(.separator())
        add(menu, "Quit AntHill", #selector(quit))
        NSApp.activate(ignoringOtherApps: true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @discardableResult
    func add(_ menu: NSMenu, _ title: String, _ sel: Selector) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        it.target = self
        menu.addItem(it)
        return it
    }

    @objc func sendAntsNow() {
        if colony.paused { togglePause() }
        sendNow = true
        scan()
    }
    @objc func openAnthill() { NSWorkspace.shared.open(Desk.anthill) }
    @objc func bringBack() {
        // remember them so the ants don't carry them off again
        spared = spared.union(Desk.restoreAll())
        colony.stored = Desk.storedCount
    }
    @objc func setGrace(_ it: NSMenuItem) { if let s = it.representedObject as? Double { grace = s } }
    @objc func togglePause() {
        colony.paused.toggle()
        defaults.set(colony.paused, forKey: "paused")
    }
    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
