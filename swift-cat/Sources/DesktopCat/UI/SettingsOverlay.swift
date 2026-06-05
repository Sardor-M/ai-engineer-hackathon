import AppKit
import SwiftUI

/// User-facing settings card, toggled by the gear button alongside the mic in
/// the cat window's corner. Surfaces the four tunables already persisted by
/// `SettingsStore`:
///
/// - **Voice** — master on/off for spoken output (`voiceEnabled`).
/// - **Profile** — the default voice character (`voiceProfile`).
/// - **Auto voice by context** — let the mode (PDF / Mail / night hours) pick
///   the character instead of the fixed default (`autoVoiceByContext`).
/// - **Mic questions** — whether the cat may ask about what's under the cursor
///   (`mouseQuestionsEnabled`).
///
/// Every edit writes straight through to `SettingsStore`, which persists to
/// `settings.json` and is read fresh by `Voice` on the next utterance — so a
/// change takes effect the next time the cat speaks, no restart needed.
///
/// Like the other panels this is a borderless, transparent, `.nonactivatingPanel`
/// `NSPanel`: it accepts clicks (toggles, profile pills) but never steals key
/// focus from the app the user was working in. Anchored to the left of the cat,
/// same edge as the active panel.
@MainActor
final class SettingsOverlay {
    static let width: CGFloat = 300
    static let height: CGFloat = 286
    /// Horizontal gap between the panel's right edge and the cat window's left edge.
    static let gap: CGFloat = 12

    private let panel: NSPanel
    private let model: SettingsOverlayModel
    private let settings: SettingsStore
    private weak var anchor: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private var hideTask: Task<Void, Never>?

    init(anchor: NSWindow, settings: SettingsStore) {
        self.anchor = anchor
        self.settings = settings

        let store = settings
        self.model = SettingsOverlayModel(
            initial: settings.current,
            persist: { next in
                store.update { $0 = next }
            }
        )

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
        p.ignoresMouseEvents = false  // toggles + profile pills need clicks
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: SettingsOverlayContent(model: model))
        hosting.frame = rect
        p.contentView = hosting

        self.panel = p

        model.requestClose = { [weak self] in self?.hide() }

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

    var isVisible: Bool { model.visible }

    /// Show the overlay, refreshing the controls from whatever's currently on
    /// disk in case something changed the settings out from under us.
    func show() {
        hideTask?.cancel()
        hideTask = nil
        model.settings = settings.current
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
            // Match the SwiftUI fade duration before orderOut to avoid a snap.
            try? await Task.sleep(nanoseconds: 240_000_000)
            if Task.isCancelled { return }
            self.panel.orderOut(nil)
        }
    }

    func toggle() {
        if model.visible {
            hide()
        } else {
            show()
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
            // If the cat is dragged to the far left and the panel would clip,
            // flip it to the right of the cat instead.
            if originX < visible.minX + 8 {
                originX = cat.maxX + Self.gap
            }
            originX = min(originX, visible.maxX - panelWidth - 8)
            originY = max(visible.minY + 8, min(originY, visible.maxY - panelHeight - 8))
        }

        panel.setFrame(
            NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight),
            display: true
        )
    }
}

// MARK: - View model

/// Single source of truth for the overlay. Mutating `settings` writes straight
/// through to disk via the `persist` closure (the `SettingsStore` itself only
/// writes when something actually changed, so redundant assignments are cheap).
@MainActor
final class SettingsOverlayModel: ObservableObject {
    @Published var visible: Bool = false
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            persist(settings)
        }
    }

    /// Set by the owning `SettingsOverlay` so the header's close button can
    /// fade the panel out through the normal hide path.
    var requestClose: (() -> Void)?

    private let persist: (Settings) -> Void

    init(initial: Settings, persist: @escaping (Settings) -> Void) {
        self.settings = initial
        self.persist = persist
    }
}

// MARK: - SwiftUI content

/// Cream card matching the speech bubble / active panel: a colored header band
/// with a close button, then a column of labeled controls.
@MainActor
struct SettingsOverlayContent: View {
    @ObservedObject var model: SettingsOverlayModel

    private static let cream = Color(red: 1.0, green: 0.97, blue: 0.92)
    private static let headerColor = Color(red: 0.45, green: 0.46, blue: 0.58)
    private static let accent = Color(red: 0.45, green: 0.46, blue: 0.58)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.15)
            controls
        }
        .frame(width: SettingsOverlay.width - 16, height: SettingsOverlay.height - 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Self.cream)
                .shadow(color: Color.black.opacity(0.20), radius: 10, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(8)
        .opacity(model.visible ? 1.0 : 0.0)
        .scaleEffect(model.visible ? 1.0 : 0.96, anchor: .trailing)
        .offset(x: model.visible ? 0 : 6)
        .animation(.easeInOut(duration: 0.22), value: model.visible)
        .frame(
            width: SettingsOverlay.width,
            height: SettingsOverlay.height,
            alignment: .center
        )
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Rectangle().fill(Self.headerColor)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 6, height: 6)
                Text("settings")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { model.requestClose?() }) {
                    Text("✕")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 36)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            toggleRow("Voice", isOn: $model.settings.voiceEnabled)
            profileRow
            toggleRow("Auto voice by context", isOn: $model.settings.autoVoiceByContext)
            toggleRow("Mic questions", isOn: $model.settings.mouseQuestionsEnabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.8))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Self.accent)
        }
    }

    private var profileRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Profile")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color.black.opacity(0.8))
            HStack(spacing: 4) {
                ForEach(VoiceProfile.allCases, id: \.self) { profile in
                    profilePill(profile)
                }
            }
            .opacity(model.settings.autoVoiceByContext ? 0.55 : 1.0)
            if model.settings.autoVoiceByContext {
                Text("Context is choosing the voice — turn off auto to pin one.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(Color.black.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func profilePill(_ profile: VoiceProfile) -> some View {
        let selected = model.settings.voiceProfile == profile
        return Button(action: { model.settings.voiceProfile = profile }) {
            Text(profile.rawValue)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(selected ? .white : Color.black.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Self.accent : Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}
