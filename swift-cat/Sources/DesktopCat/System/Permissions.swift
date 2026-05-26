import AppKit
import ApplicationServices
import CoreGraphics

enum CatPermission: String, CaseIterable, Sendable {
    case screenRecording = "Screen Recording"
    case accessibility = "Accessibility"
    case automation = "Automation"

    /// macOS doesn't have a reliable "is granted" check for Automation outside
    /// of actually invoking AppleScript and inspecting the error. Treat it as
    /// "unknown — first use will prompt", which matches the user experience.
    func isGranted() -> Bool {
        switch self {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess()
        case .accessibility:
            return AXIsProcessTrusted()
        case .automation:
            return true
        }
    }

    /// Deep link to the relevant System Settings (System Preferences) pane.
    var settingsURL: URL? {
        switch self {
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .automation:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }
}

enum Permissions {
    /// Logs the current state of each TCC permission to the terminal. Phase 4
    /// will surface this in the settings overlay instead.
    static func preflight() {
        for p in CatPermission.allCases {
            let ok = p.isGranted()
            print("[cat] permission \(p.rawValue): \(ok ? "granted" : "not granted (will prompt on first use)")")
        }
    }

    static func openSettings(for permission: CatPermission) {
        if let url = permission.settingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
