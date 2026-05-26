import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory: no Dock icon, no global menu in the menu bar.
// Keyboard shortcuts (e.g. Cmd+Q) still resolve through NSApp.mainMenu.
app.setActivationPolicy(.accessory)
app.run()
