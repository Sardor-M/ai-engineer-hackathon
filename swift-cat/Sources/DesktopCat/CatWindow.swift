import AppKit

/// Borderless, transparent, always-on-top window that hosts the cat.
/// Matches the Electron version: 240×240, anchored bottom-right of the
/// primary display, follows the user across Spaces.
final class CatWindow: NSWindow {

    init() {
        let size = NSSize(width: 240, height: 240)
        let rect = NSRect(origin: .zero, size: size)

        super.init(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.ignoresMouseEvents = false
        self.isMovableByWindowBackground = false   // we handle drag manually
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary
        ]

        let view = CatView(frame: rect)
        self.contentView = view

        positionAtBottomRight()
    }

    private func positionAtBottomRight() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        let origin = NSPoint(
            x: v.maxX - frame.width - 20,
            y: v.minY + 60
        )
        setFrameOrigin(origin)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
