import AppKit
import QuartzCore

/// Hosts the stacked sprite CALayers and handles drag/click. State is driven
/// from outside via `setState(_:)`; click without drag invokes `onClick` so
/// the coordinator decides what a click means (Phase 2: wake + capture proof;
/// Phase 3: proactive brain call).
final class CatView: NSView {

    /// Fires once per click-without-drag.
    var onClick: (() -> Void)?

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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.masksToBounds = false
        layer = root

        setupSprites()
        startBreathing()
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
            print("[cat] missing sprite: \(name).png")
            return nil
        }
        guard let img = NSImage(contentsOf: url) else {
            print("[cat] failed to decode: \(name).png")
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

    // Default hit test (whole bounds) is fine for Phase 1 — matches Electron.
}
