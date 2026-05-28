import AppKit
import SwiftUI

/// Wider companion to the speech bubble — a panel anchored to the cat
/// window's left edge that shows the *full* output of a context-driven brain
/// call:
///
/// - PDF mode: blue header + a single scrollable body with the full summary.
///   The speech bubble still surfaces the first 1–2 sentences for voice; the
///   panel lets the user read the rest.
/// - Email mode: pink header + three tabs (Summary / Reply / Ask) with a
///   Copy button on the Reply tab.
///
/// The panel is borderless, transparent, and floats above other windows. It
/// accepts mouse events (tabs, Copy) so `ignoresMouseEvents` is false — but
/// because it uses `.nonactivatingPanel` it never steals key focus from the
/// app the user was working in.
///
/// Lifecycle is fully driven by the coordinator: `show(pdf:)` / `show(email:)`
/// fades in, `hide()` fades out. No internal timers — the panel stays put
/// until the coordinator says otherwise.
@MainActor
final class ActivePanel {
    static let width: CGFloat = 360
    static let height: CGFloat = 320
    /// Horizontal gap between the panel's right edge and the cat window's
    /// left edge.
    static let gap: CGFloat = 12

    private let panel: NSPanel
    private let model = ActivePanelModel()
    private weak var anchor: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?

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
        p.ignoresMouseEvents = false  // tabs + Copy need clicks
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: ActivePanelContent(model: model))
        hosting.frame = rect
        p.contentView = hosting

        self.panel = p

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: anchor,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reposition()
            }
        }

        reposition()
    }

    deinit {
        if let m = moveObserver {
            NotificationCenter.default.removeObserver(m)
        }
        let p = self.panel
        DispatchQueue.main.async {
            p.close()
        }
    }

    // MARK: - Public API

    /// Show the full PDF summary in blue-header mode. Replaces any current
    /// content. Coordinator calls this from `runPdfSummary` once the brain
    /// returns a non-empty summary.
    func show(pdf summary: String) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hideTask?.cancel()
        hideTask = nil

        model.mode = .pdf(trimmed)
        model.selectedTab = .summary  // reset for next email
        model.copyFeedback = false
        model.visible = true
        panel.orderFrontRegardless()
        reposition()
    }

    /// Show the email Summary / Reply / Ask tabs in pink-header mode.
    /// Selects the Summary tab on entry.
    func show(email result: EmailResult) {
        hideTask?.cancel()
        hideTask = nil

        model.mode = .email(result)
        model.selectedTab = .summary
        model.copyFeedback = false
        model.visible = true
        panel.orderFrontRegardless()
        reposition()
    }

    /// Fade out and order out. Idempotent.
    func hide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            guard let self else { return }
            self.model.visible = false
            // Match the SwiftUI fade duration before orderOut to avoid snap.
            try? await Task.sleep(nanoseconds: 280_000_000)
            if Task.isCancelled { return }
            self.panel.orderOut(nil)
            self.model.mode = .idle
        }
    }

    // MARK: - Positioning

    private func reposition() {
        guard let anchor else { return }
        let cat = anchor.frame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        var originX = cat.minX - panelWidth - Self.gap
        var originY = cat.midY - panelHeight / 2

        let screen = anchor.screen ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            // Clamp horizontally — if the cat is dragged to the far left and
            // the panel would go off-screen, slide it to the right of the cat
            // instead.
            if originX < visible.minX + 8 {
                originX = cat.maxX + Self.gap
            }
            originX = min(originX, visible.maxX - panelWidth - 8)
            // Clamp vertically.
            originY = max(visible.minY + 8, min(originY, visible.maxY - panelHeight - 8))
        }

        panel.setFrame(
            NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight),
            display: true
        )
    }
}

// MARK: - View model

/// Single source of truth for what the SwiftUI content renders. `@MainActor`
/// on the owner ensures only main-thread mutation; SwiftUI observes via
/// `@Published`.
@MainActor
final class ActivePanelModel: ObservableObject {
    enum Mode: Equatable {
        case idle
        case pdf(String)
        case email(EmailResult)
    }

    enum Tab: String, CaseIterable {
        case summary, reply, ask

        var label: String {
            switch self {
            case .summary: return "Summary"
            case .reply: return "Reply"
            case .ask: return "Ask"
            }
        }
    }

    @Published var mode: Mode = .idle
    @Published var selectedTab: Tab = .summary
    @Published var visible: Bool = false
    /// Flips true briefly after the user taps Copy, so the button reads
    /// "Copied" then reverts to "Copy".
    @Published var copyFeedback: Bool = false
}

// MARK: - SwiftUI content

/// Card layout: a colored header band, a divider, then the mode-specific
/// body. Fades + scales in/out tied to `model.visible`.
@MainActor
struct ActivePanelContent: View {
    @ObservedObject var model: ActivePanelModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            modeBody
        }
        .frame(width: ActivePanel.width - 16, height: ActivePanel.height - 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 1.0, green: 0.97, blue: 0.92))
                .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(8)
        .opacity(model.visible ? 1.0 : 0.0)
        .scaleEffect(model.visible ? 1.0 : 0.96, anchor: .trailing)
        .offset(x: model.visible ? 0 : 6)
        .animation(.easeInOut(duration: 0.24), value: model.visible)
        .animation(.easeInOut(duration: 0.18), value: model.mode)
        .frame(
            width: ActivePanel.width,
            height: ActivePanel.height,
            alignment: .center
        )
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(headerColor)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 6, height: 6)
                Text(headerTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .textCase(.lowercase)
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 36)
    }

    private var headerColor: Color {
        switch model.mode {
        case .pdf:   return Color(red: 0.36, green: 0.52, blue: 0.86)
        case .email: return Color(red: 0.94, green: 0.55, blue: 0.72)
        case .idle:  return Color.gray.opacity(0.30)
        }
    }

    private var headerTitle: String {
        switch model.mode {
        case .pdf:   return "reading"
        case .email: return "letter"
        case .idle:  return ""
        }
    }

    // MARK: Body

    @ViewBuilder
    private var modeBody: some View {
        switch model.mode {
        case .pdf(let summary):
            pdfBody(summary)
        case .email(let result):
            emailBody(result)
        case .idle:
            Color.clear
        }
    }

    private func pdfBody(_ summary: String) -> some View {
        ScrollView {
            Text(summary)
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(Color.black.opacity(0.85))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emailBody(_ result: EmailResult) -> some View {
        VStack(spacing: 0) {
            tabPicker
            ScrollView {
                Text(text(for: model.selectedTab, in: result))
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.selectedTab == .reply && !result.draftReply.isEmpty {
                copyBar(text: result.draftReply)
            }
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 4) {
            ForEach(ActivePanelModel.Tab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: ActivePanelModel.Tab) -> some View {
        Button(action: { model.selectedTab = tab }) {
            Text(tab.label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(model.selectedTab == tab ? .white : Color.black.opacity(0.65))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            model.selectedTab == tab
                                ? Color(red: 0.94, green: 0.55, blue: 0.72)
                                : Color.black.opacity(0.05)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func text(for tab: ActivePanelModel.Tab, in result: EmailResult) -> String {
        let v: String
        switch tab {
        case .summary: v = result.summary
        case .reply:   v = result.draftReply
        case .ask:     v = result.clarifyingQuestion
        }
        return v.isEmpty ? "(empty — the model didn't return this field)" : v
    }

    private func copyBar(text: String) -> some View {
        HStack {
            Spacer()
            Button(action: { copyToPasteboard(text) }) {
                Text(model.copyFeedback ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.72))
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .padding(.bottom, 10)
            .animation(.easeInOut(duration: 0.18), value: model.copyFeedback)
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        model.copyFeedback = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            model.copyFeedback = false
        }
    }
}
