import Foundation

/// Resolves and creates `~/Library/Application Support/DesktopCat/` lazily.
enum AppSupport {
    static let dir: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("DesktopCat", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func file(_ name: String) -> URL {
        dir.appendingPathComponent(name)
    }
}
