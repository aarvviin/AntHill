import AppKit

// Finds screenshots on the Desktop, asks Finder where their icons are, and moves files in and out of the anthill.
enum Desk {
    static let fm = FileManager.default
    static var desktop: URL { fm.urls(for: .desktopDirectory, in: .userDomainMask)[0] }
    static var anthill: URL {
        let u = fm.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent("Anthill")
        try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // macOS tags every screenshot and screen recording with this metadata attribute
    static func isScreenshot(_ u: URL) -> Bool {
        getxattr(u.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
    }

    // screenshots older than `grace` seconds, oldest first
    static func screenshots(olderThan grace: TimeInterval, sparing spared: Set<String>) -> [URL] {
        let keys: [URLResourceKey] = [.creationDateKey, .isRegularFileKey]
        let list = (try? fm.contentsOfDirectory(at: desktop, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let now = Date()
        return list.compactMap { u -> (URL, Date)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  !spared.contains(u.lastPathComponent), isScreenshot(u) else { return nil }
            let born = v.creationDate ?? now
            return now.timeIntervalSince(born) >= grace ? (u, born) : nil
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }

    // icon center in Finder's desktop coordinates (top-left of the main screen)
    static func position(of name: String) -> CGPoint? {
        let esc = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        guard let r = NSAppleScript(source: "tell application \"Finder\" to get desktop position of item \"\(esc)\" of desktop")?
                .executeAndReturnError(&err), err == nil, r.numberOfItems >= 2,
              let x = r.atIndex(1)?.int32Value, let y = r.atIndex(2)?.int32Value, x >= 0, y >= 0 else { return nil }
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    static func thumbnail(_ u: URL) -> NSImage {
        if let img = NSImage(contentsOf: u), img.size.width > 0 { return img }
        return NSWorkspace.shared.icon(forFile: u.path)
    }

    static func freeName(_ name: String, in dir: URL) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var dst = dir.appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: dst.path) {
            dst = dir.appendingPathComponent("\(base) \(n)" + (ext.isEmpty ? "" : "." + ext))
            n += 1
        }
        return dst
    }

    static func haul(_ u: URL) -> Bool {
        guard fm.fileExists(atPath: u.path) else { return false }
        return (try? fm.moveItem(at: u, to: freeName(u.lastPathComponent, in: anthill))) != nil
    }

    static var storedCount: Int {
        ((try? fm.contentsOfDirectory(atPath: anthill.path)) ?? []).filter { !$0.hasPrefix(".") }.count
    }

    // moves everything back to the Desktop and returns the names it ended up with
    static func restoreAll() -> [String] {
        let files = (try? fm.contentsOfDirectory(at: anthill, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        var names: [String] = []
        for f in files {
            let dst = freeName(f.lastPathComponent, in: desktop)
            if (try? fm.moveItem(at: f, to: dst)) != nil { names.append(dst.lastPathComponent) }
        }
        return names
    }
}
