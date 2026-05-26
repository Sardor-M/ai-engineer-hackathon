import AppKit
import ApplicationServices

/// What we know about the user's foreground at any moment.
struct FrontmostContext: Equatable, Sendable {
    let appName: String
    let bundleID: String?
    let title: String?

    /// Classify the same way the Electron version does. Title is consulted
    /// only for browsers that might be viewing a PDF.
    var mode: CatMode {
        let n = appName.lowercased()
        let t = (title ?? "").lowercased()
        if n == "mail" { return .email }
        if n == "preview" || n.contains("acrobat") { return .pdf }
        let browsers: Set<String> = [
            "google chrome", "safari", "arc",
            "brave browser", "microsoft edge", "firefox"
        ]
        if browsers.contains(n) && t.contains(".pdf") { return .pdf }
        return .idle
    }
}

/// Observes the frontmost application via NSWorkspace and polls the focused
/// window title (Accessibility API). Calls `onChange` whenever app or title
/// changes. Polling is cheap (1s) and degrades gracefully when Accessibility
/// permission is denied — `title` is simply `nil` in that case.
@MainActor
final class FrontmostWatcher {
    var onChange: ((FrontmostContext) -> Void)?

    private var observer: NSObjectProtocol?
    private var titleTimer: Timer?
    private var lastContext: FrontmostContext?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleActivation(note) }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            emit(for: app)
        }

        titleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshTitle() }
        }
    }

    func stop() {
        if let o = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        observer = nil
        titleTimer?.invalidate()
        titleTimer = nil
    }

    private func handleActivation(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        emit(for: app)
    }

    private func refreshTitle() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        emit(for: app)
    }

    private func emit(for app: NSRunningApplication) {
        let ctx = FrontmostContext(
            appName: app.localizedName ?? "",
            bundleID: app.bundleIdentifier,
            title: focusedWindowTitle(for: app)
        )
        guard ctx != lastContext else { return }
        lastContext = ctx
        onChange?(ctx)
    }

    /// Returns the focused window's title via the Accessibility API. Silently
    /// returns nil if AX access is denied — the cat still works on app name.
    private func focusedWindowTitle(for app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)

        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            axApp,
            kAXFocusedWindowAttribute as CFString,
            &focusedRef
        )
        guard focusedResult == .success, let focused = focusedRef else { return nil }

        // Bridge the CFTypeRef to AXUIElement safely.
        let window = unsafeBitCast(focused, to: AXUIElement.self)

        var titleRef: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            window,
            kAXTitleAttribute as CFString,
            &titleRef
        )
        guard titleResult == .success else { return nil }
        return titleRef as? String
    }
}
