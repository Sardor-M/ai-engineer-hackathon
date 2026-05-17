import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var catWindow: CatWindow?
    private var coordinator: CatCoordinator?
    private var settings: SettingsStore?
    private var memory: MemoryStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenuShortcuts()

        let s = SettingsStore()
        let m = MemoryStore()
        self.settings = s
        self.memory = m

        let window = CatWindow()
        window.makeKeyAndOrderFront(nil)
        self.catWindow = window

        if let view = window.contentView as? CatView {
            let brain = Brain.defaultStack()
            let c = CatCoordinator(catView: view, settings: s, memory: m, brain: brain)
            c.start()
            self.coordinator = c
        } else {
            print("[cat] WARNING: contentView is not a CatView — coordinator not started")
        }

        // Surface the cat on first launch so it's visible immediately.
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }

    /// .accessory policy hides the menu bar, but NSApp.mainMenu still resolves
    /// keyEquivalents. We install one item — Quit — so Cmd+Q exits cleanly.
    private func installMenuShortcuts() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appSubmenu = NSMenu()
        appSubmenu.addItem(
            withTitle: "Quit DesktopCat",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appSubmenu

        NSApp.mainMenu = mainMenu
    }
}
