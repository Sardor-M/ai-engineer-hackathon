import AppKit
import QuartzCore

/// Small circular settings affordance that sits just left of the `MicButton`
/// in the cat window's bottom-right corner. Same reveal-on-hover behavior as
/// the mic button, minus the listening/pulse state — a single click toggles
/// the settings overlay via `onTap`.
///
/// Stays a child view of `CatView` so its frame moves with the cat window.
@MainActor
final class GearButton: NSView {

    /// Fires once per click. The coordinator wires this to the settings
    /// overlay's `toggle()`.
    var onTap: (() -> Void)?

    private let circle = CALayer()
    private let glyph = CATextLayer()

    init() {
        // 30×30 — a touch smaller than the 36 pt mic so the mic reads as the
        // primary affordance and the gear as secondary.
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        wantsLayer = true
        configureLayers()
        layer?.opacity = 0  // hidden until hover
    }

    required init?(coder: NSCoder) {
        fatalError("GearButton does not support coder-based init")
    }

    // MARK: - Public state

    /// Show / hide the button. `CatView` calls this on mouse-entered /
    /// mouse-exited so the gear is invisible unless the user is hovering.
    func setRevealed(_ on: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeInEaseOut)
        )
        layer?.opacity = on ? 1.0 : 0.0
        CATransaction.commit()
    }

    // MARK: - Hit testing

    override func mouseDown(with event: NSEvent) {
        // Swallow the event so CatView's drag handler doesn't grab it.
        onTap?()
    }

    override func mouseDragged(with event: NSEvent) {
        // No-op. The button itself shouldn't drag the window.
    }

    override func mouseUp(with event: NSEvent) {
        // Click already fired on mouseDown; just absorb the up.
    }

    // MARK: - Layer setup

    private func configureLayers() {
        circle.frame = bounds
        circle.cornerRadius = bounds.width / 2
        circle.borderWidth = 0.5
        circle.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        circle.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        layer?.addSublayer(circle)

        // Inset a few pt so the glyph sits centered — CATextLayer baselines
        // high otherwise (same trick as MicButton).
        glyph.frame = bounds.insetBy(dx: 0, dy: 4)
        glyph.alignmentMode = .center
        glyph.foregroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        glyph.fontSize = 15
        glyph.font = NSFont.systemFont(ofSize: 15) as CFTypeRef
        glyph.string = "⚙"   // gear glyph — replaced by SF Symbol if/when we add asset support
        glyph.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        layer?.addSublayer(glyph)
    }
}
