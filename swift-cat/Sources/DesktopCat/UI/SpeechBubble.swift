import AppKit
import SwiftUI

/// Cream-colored speech bubble that floats over the cat. Renders SwiftUI
/// content inside a borderless `NSPanel` so it can sit on top of the cat
/// window without grabbing focus.
///
/// Positioning: anchored to the cat window's top edge, extending leftward
/// (the cat lives bottom-right, so the bubble has room on its left). Tracks
/// `NSWindow.didMoveNotification` on the cat so dragging the cat carries
/// the bubble along.
///
/// The bubble does no timing of its own — `show` and `hide` are explicit
/// and the coordinator wires `hide` to voice playback finishing.
@MainActor
final class SpeechBubble {
    static let width: CGFloat = 320
    static let height: CGFloat = 140

    private let panel: NSPanel
    private let model = SpeechBubbleModel()
    private weak var anchor: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?
    private var currentUtteranceID: UUID?

    init(anchor: NSWindow) {
        self.anchor = anchor

        let size = NSSize(width: Self.width, height: Self.height)
        let rect = NSRect(origin: .zero, size: size)
        let p = NSPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: SpeechBubbleContent(model: model))
        hosting.frame = rect
        p.contentView = hosting

        self.panel = p

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: anchor,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }

        reposition()
    }

    deinit {
        if let m = moveObserver {
            NotificationCenter.default.removeObserver(m)
        }
    }

    /// Show `text`. Replaces any current text. Returns a UUID that the caller
    /// should pass to `hide(id:)` so stale `onDone` callbacks from a previous
    /// utterance cannot hide a newer bubble.
    @discardableResult
    func show(_ text: String) -> UUID {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { hide(); return UUID() }
        hideTask?.cancel()
        hideTask = nil

        let id = UUID()
        currentUtteranceID = id

        model.text = trimmed
        model.visible = true
        panel.orderFrontRegardless()
        reposition()
        return id
    }

    /// Fade out and order out. Pass the `id` returned by `show(_:)` so that a
    /// stale `onDone` from a previous utterance cannot hide a newer bubble.
    /// When `id` is `nil` (barge-in path) the bubble hides unconditionally.
    func hide(id: UUID? = nil, after delay: TimeInterval = 0) {
        if let id, id != currentUtteranceID { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled { return }
            }
            guard let self else { return }
            self.model.visible = false
            // Match the SwiftUI fade duration before we orderOut so we don't
            // snap to invisible mid-animation.
            try? await Task.sleep(nanoseconds: 260_000_000)
            if Task.isCancelled { return }
            self.panel.orderOut(nil)
        }
    }

    private func reposition() {
        guard let anchor else { return }
        let cat = anchor.frame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        // Tail sits 30pt from the bubble's trailing edge; we want it just
        // above the cat's head, near the horizontal midpoint of the cat
        // window. The bubble extends leftward from there.
        let tailInsetFromRight: CGFloat = 30
        let tailScreenX = cat.midX
        let originX = tailScreenX - (panelWidth - tailInsetFromRight)

        // Bubble bottom sits just above the cat's head with a small overlap.
        let originY = cat.maxY - 30

        let clampedX: CGFloat
        if let visible = NSScreen.main?.visibleFrame {
            clampedX = max(visible.minX + 8, min(originX, visible.maxX - panelWidth - 8))
        } else {
            clampedX = originX
        }

        panel.setFrame(
            NSRect(x: clampedX, y: originY, width: panelWidth, height: panelHeight),
            display: true
        )
    }
}

/// Single-source-of-truth view model. SwiftUI observes these, and the
/// `@MainActor` annotation on the owning `SpeechBubble` keeps mutation safe.
@MainActor
final class SpeechBubbleModel: ObservableObject {
    @Published var text: String = ""
    @Published var visible: Bool = false
}

/// Rounded cream card with a small tail. Width is fixed; height grows with
/// text wrap. The panel is taller than needed so SwiftUI's layout has slack.
struct SpeechBubbleContent: View {
    @ObservedObject var model: SpeechBubbleModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(model.text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(Color.black.opacity(0.85))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: SpeechBubble.width - 16, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 1.0, green: 0.97, blue: 0.92))
                        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                )

            BubbleTail()
                .fill(Color(red: 1.0, green: 0.97, blue: 0.92))
                .frame(width: 16, height: 8)
                .padding(.trailing, 22)
        }
        .padding(8)
        .opacity(model.visible ? 1.0 : 0.0)
        .scaleEffect(model.visible ? 1.0 : 0.96, anchor: .bottomTrailing)
        .animation(.easeInOut(duration: 0.22), value: model.visible)
        .animation(.easeInOut(duration: 0.18), value: model.text)
        .frame(
            width: SpeechBubble.width,
            height: SpeechBubble.height,
            alignment: .bottomTrailing
        )
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
