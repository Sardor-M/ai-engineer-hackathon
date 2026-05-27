import AppKit
import QuartzCore

/// Small circular mic affordance that appears in the cat window's
/// bottom-right corner. Replaces the `Cmd+Shift+L` hotkey from Phase 3c.
///
/// Behavior:
/// - Invisible by default. Fades in when the cursor enters the cat window
///   and fades out shortly after it leaves.
/// - Pulses red while the listener is active.
/// - Click toggles listening via `onToggle`. The coordinator wires this
///   to `Listener.toggle`.
///
/// Stays a child view of `CatView` so its frame moves with the cat window.
@MainActor
final class MicButton: NSView {

    /// Fires when the user clicks the button. The coordinator decides whether
    /// to start or stop listening (the button has no opinion).
    var onToggle: (() -> Void)?

    private let circle = CALayer()
    private let glyph = CATextLayer()
    private var trackingArea: NSTrackingArea?
    private var revealed = false
    private var listening = false

    init() {
        // 36×36 affordance — large enough to click reliably, small enough not
        // to crowd the cat.
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        wantsLayer = true
        configureLayers()
        layer?.opacity = 0  // hidden until hover
    }

    required init?(coder: NSCoder) {
        fatalError("MicButton does not support coder-based init")
    }

    // MARK: - Public state

    /// Toggle the pulsing-red "listening" look. Called by the coordinator
    /// from `Listener` start/stop transitions so the visual stays in sync
    /// with the real listener state (which may be set by hotkey too).
    func setListening(_ on: Bool) {
        guard on != listening else { return }
        listening = on
        if on {
            applyListeningStyle()
            startPulse()
        } else {
            stopPulse()
            applyIdleStyle()
        }
    }

    /// Show / hide the button. The CatView calls this on mouse-entered /
    /// mouse-exited so the button is invisible unless the user is hovering.
    /// While listening the button stays visible regardless of hover so the
    /// user can see they're being recorded.
    func setRevealed(_ on: Bool) {
        revealed = on
        let target: Float = (on || listening) ? 1.0 : 0.0
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeInEaseOut)
        )
        layer?.opacity = target
        CATransaction.commit()
    }

    // MARK: - Hit testing

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        // Swallow the event so CatView's drag handler doesn't grab it.
        onToggle?()
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
        layer?.addSublayer(circle)

        glyph.frame = bounds
        glyph.alignmentMode = .center
        glyph.foregroundColor = NSColor.white.cgColor
        glyph.fontSize = 18
        glyph.font = NSFont.systemFont(ofSize: 18) as CFTypeRef
        glyph.string = "●"   // simple dot — replaced by SF Symbol if/when we add asset support
        glyph.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        // Center the text vertically — CATextLayer baselines high otherwise.
        glyph.frame = bounds.insetBy(dx: 0, dy: 5)
        layer?.addSublayer(glyph)

        applyIdleStyle()
    }

    private func applyIdleStyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circle.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        circle.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        glyph.foregroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
        CATransaction.commit()
    }

    private func applyListeningStyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        circle.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        circle.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        glyph.foregroundColor = NSColor.white.cgColor
        CATransaction.commit()
    }

    private func startPulse() {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.18
        pulse.duration = 0.7
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        circle.add(pulse, forKey: "pulse")

        // Re-trigger reveal so the button shows up even if the user isn't
        // hovering. Coordinator may also call this for safety.
        setRevealed(revealed)
    }

    private func stopPulse() {
        circle.removeAnimation(forKey: "pulse")
    }

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) {
        setRevealed(true)
    }

    override func mouseExited(with event: NSEvent) {
        setRevealed(false)
    }
}
