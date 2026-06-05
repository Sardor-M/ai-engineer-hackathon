import AppKit
import QuartzCore

/// Hosts the stacked sprite CALayers and handles drag/click. State is driven
/// from outside via `setState(_:)`; click without drag invokes `onClick` so
/// the coordinator decides what a click means (Phase 2: wake + capture proof;
/// Phase 3: proactive brain call).
final class CatView: NSView {

    /// Fires once per click-without-drag.
    var onClick: (() -> Void)?

    /// Mic affordance overlay in the bottom-right corner. Coordinator wires
    /// its `onToggle` to the listener.
    let micButton = MicButton()

    /// Settings affordance, tucked just left of the mic. Coordinator wires its
    /// `onTap` to the settings overlay.
    let gearButton = GearButton()

    private let puddleLayer = CALayer()
    private let awakeLayer  = CALayer()

    /// Map state → layer. Add new entries here as more sprites come online.
    private lazy var spriteLayers: [CatSpriteState: CALayer] = [
        .puddle: puddleLayer,
        .awake: awakeLayer
    ]

    private var currentState: CatSpriteState = .puddle

    private var dragMouseStart: NSPoint = .zero
    private var dragWindowStart: NSPoint = .zero
    private var didDrag = false

    private var hoverTracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.masksToBounds = false
        layer = root

        setupSprites()
        startBreathing()
        setupCornerButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("CatView does not support coder-based init")
    }

    // MARK: - Sprite stack

    private func setupSprites() {
        let inset: CGFloat = 10
        let spriteFrame = bounds.insetBy(dx: inset, dy: inset)

        for (_, spriteLayer) in spriteLayers {
            spriteLayer.frame = spriteFrame
            spriteLayer.contentsGravity = .resizeAspect
            spriteLayer.opacity = 0
            spriteLayer.shadowColor = NSColor.black.cgColor
            spriteLayer.shadowOpacity = 0.42
            spriteLayer.shadowOffset = CGSize(width: 0, height: -8)
            spriteLayer.shadowRadius = 12
            layer?.addSublayer(spriteLayer)
        }

        puddleLayer.contents = loadSprite("cat_puddle")
        awakeLayer.contents  = loadSprite("cat_awake")

        spriteLayers[currentState]?.opacity = 1
    }

    private func loadSprite(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else {
            Log.cat.error("missing sprite: \(name).png")
            return nil
        }
        guard let img = NSImage(contentsOf: url) else {
            Log.cat.error("failed to decode: \(name).png")
            return nil
        }
        var rect = NSRect(origin: .zero, size: img.size)
        return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func startBreathing() {
        let anim = CABasicAnimation(keyPath: "transform.scale")
        anim.fromValue = 1.0
        anim.toValue   = 1.035
        anim.duration  = 1.8
        anim.autoreverses = true
        anim.repeatCount  = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        for (_, spriteLayer) in spriteLayers {
            spriteLayer.add(anim, forKey: "breathe")
        }
    }

    /// Crossfade to a new sprite state.
    func setState(_ next: CatSpriteState) {
        guard next != currentState else { return }
        guard spriteLayers[next] != nil else { return }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.26)
        CATransaction.setAnimationTimingFunction(
            CAMediaTimingFunction(name: .easeInEaseOut)
        )
        for (state, spriteLayer) in spriteLayers {
            spriteLayer.opacity = (state == next) ? 1 : 0
        }
        CATransaction.commit()

        currentState = next
    }

    // MARK: - Drag + click

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        dragMouseStart  = NSEvent.mouseLocation
        dragWindowStart = window.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragMouseStart.x
        let dy = mouse.y - dragMouseStart.y
        if abs(dx) + abs(dy) > 2 { didDrag = true }
        let newOrigin = NSPoint(
            x: dragWindowStart.x + dx,
            y: dragWindowStart.y + dy
        )
        window.setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onClick?() }
    }

    // MARK: - Corner buttons (mic — Phase 4a, gear — Phase 4c)

    private func setupCornerButtons() {
        // Bottom-right of the cat window, tucked a few pt from the edge so
        // they don't fight the sprite's silhouette. The gear sits just left of
        // the mic, vertically centered against it.
        let inset: CGFloat = 14
        let gap: CGFloat = 8

        let micX = bounds.maxX - micButton.frame.width - inset
        micButton.frame = NSRect(
            x: micX,
            y: inset,
            width: micButton.frame.width,
            height: micButton.frame.height
        )
        addSubview(micButton)

        let gearX = micX - gap - gearButton.frame.width
        let gearY = inset + (micButton.frame.height - gearButton.frame.height) / 2
        gearButton.frame = NSRect(
            x: gearX,
            y: gearY,
            width: gearButton.frame.width,
            height: gearButton.frame.height
        )
        addSubview(gearButton)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverTracking {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        micButton.setRevealed(true)
        gearButton.setRevealed(true)
    }

    override func mouseExited(with event: NSEvent) {
        micButton.setRevealed(false)
        gearButton.setRevealed(false)
    }
}
