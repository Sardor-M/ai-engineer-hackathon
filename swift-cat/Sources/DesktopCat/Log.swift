import Foundation
import os

/// Category-based logger. Every line goes to BOTH stdout and the unified
/// logging system so the same code is debuggable across launch methods:
///
/// - `./build/DesktopCat.app/Contents/MacOS/DesktopCat` — direct exec attaches
///   stdout to the terminal; you see the `[category] message` lines there.
/// - `open build/DesktopCat.app` — stdout is detached, but the unified-log
///   stream picks up the same lines: Console.app filtered by subsystem
///   `com.amelia.desktopcat`, or
///   `log stream --process DesktopCat --info`.
///
/// `os.Logger` redacts interpolated values by default (`.private`) so raw
/// payloads can never leak into the unified log even if a call site
/// accidentally passes unsanitised content. Use the `*Public` variants only
/// when the message is confirmed non-sensitive (e.g. status codes, enum tags,
/// already-fingerprinted metadata strings).
enum Log {
    private static let subsystem = "com.amelia.desktopcat"

    static let cat      = Category("cat")
    static let listener = Category("listener")
    static let voice    = Category("voice")
    static let brain    = Category("brain")
    static let env      = Category("env")

    /// Wraps a sensitive string so logging helpers can emit only
    /// length + fingerprint metadata rather than the raw content.
    /// Use for screen captures, mail bodies, or any user-derived text.
    struct Sensitive {
        let count: Int
        let fingerprint: String

        init(_ s: String) {
            count = s.count
            fingerprint = String(s.hashValue, radix: 16)
        }

        var metadata: String { "len=\(count) fp=\(fingerprint)" }
    }

    struct Category {
        let name: String
        private let logger: Logger

        init(_ name: String) {
            self.name = name
            self.logger = Logger(subsystem: Log.subsystem, category: name)
        }

        // MARK: Default (private) — safe for any message

        /// Log an informational message. Content is redacted in Console.app;
        /// still visible via stdout when running from terminal.
        func info(_ message: String) {
            print("[\(name)] \(message)")
            logger.info("\(message, privacy: .private)")
        }

        func warn(_ message: String) {
            print("[\(name)] WARN: \(message)")
            logger.warning("\(message, privacy: .private)")
        }

        func error(_ message: String) {
            print("[\(name)] ERROR: \(message)")
            logger.error("\(message, privacy: .private)")
        }

        // MARK: Explicit public opt-in — use only for confirmed non-sensitive strings

        func infoPublic(_ message: String) {
            print("[\(name)] \(message)")
            logger.info("\(message, privacy: .public)")
        }

        func warnPublic(_ message: String) {
            print("[\(name)] WARN: \(message)")
            logger.warning("\(message, privacy: .public)")
        }

        func errorPublic(_ message: String) {
            print("[\(name)] ERROR: \(message)")
            logger.error("\(message, privacy: .public)")
        }

        // MARK: Sensitive payload helpers — always emits metadata only, visible in Console.app

        func info(sensitive label: String, _ payload: Log.Sensitive) {
            let msg = "\(label) \(payload.metadata)"
            print("[\(name)] \(msg)")
            logger.info("\(msg, privacy: .public)")
        }

        func error(sensitive label: String, _ payload: Log.Sensitive) {
            let msg = "\(label) \(payload.metadata)"
            print("[\(name)] ERROR: \(msg)")
            logger.error("\(msg, privacy: .public)")
        }
    }
}
