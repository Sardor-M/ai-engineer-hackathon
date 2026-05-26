import Foundation

struct MailSelection: Sendable, Equatable {
    let subject: String
    let sender: String
    let body: String
}

/// Reads the currently selected message in Mail.app via NSAppleScript. The
/// AppleScript is identical to the Electron version so the user only grants
/// Automation → Mail permission once across both implementations.
enum MailReader {
    private static let script = """
    tell application "Mail"
      try
        set sel to selection
        if (count of sel) is 0 then return ""
        set msg to item 1 of sel
        set s to subject of msg
        set f to (sender of msg) as string
        set b to content of msg
        return s & "|||SEP|||" & f & "|||SEP|||" & b
      on error
        return ""
      end try
    end tell
    """

    private static let separator = "|||SEP|||"

    /// Runs off-thread to avoid blocking the main run loop while AppleScript
    /// hands control to Mail. Returns nil if no message is selected, Mail is
    /// closed, or the user has denied Automation → Mail.
    static func readSelected() async -> MailSelection? {
        await Task.detached(priority: .userInitiated) {
            guard let appleScript = NSAppleScript(source: script) else { return nil }
            var errorDict: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&errorDict)
            if let err = errorDict {
                print("[cat] mail applescript error:", err)
                return nil
            }
            guard
                let raw = descriptor.stringValue,
                !raw.isEmpty
            else { return nil }
            let parts = raw.components(separatedBy: separator)
            guard parts.count >= 3 else { return nil }
            return MailSelection(
                subject: parts[0],
                sender: parts[1],
                body: String(parts[2].prefix(6000))
            )
        }.value
    }
}
