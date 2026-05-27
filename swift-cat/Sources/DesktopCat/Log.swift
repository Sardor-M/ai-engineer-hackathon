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
/// `os.Logger` redacts interpolated values by default; we mark everything
/// `.public` so log output is readable in Console.app. This is fine because
/// nothing the cat logs is itself sensitive (we already truncate captures
/// and email bodies to lengths / fingerprints).
enum Log {
    private static let subsystem = "com.amelia.desktopcat"

    static let cat      = Category("cat")
    static let listener = Category("listener")
    static let voice    = Category("voice")
    static let brain    = Category("brain")
    static let env      = Category("env")

    struct Category {
        let name: String
        private let logger: Logger

        init(_ name: String) {
            self.name = name
            self.logger = Logger(subsystem: Log.subsystem, category: name)
        }

        /// Normal informational line — what the cat is doing.
        func info(_ message: String) {
            print("[\(name)] \(message)")
            logger.info("\(message, privacy: .public)")
        }

        /// Something off but not fatal. Prefixed `WARN:` in stdout to match
        /// the unified-log level rendering.
        func warn(_ message: String) {
            print("[\(name)] WARN: \(message)")
            logger.warning("\(message, privacy: .public)")
        }

        /// A failed network call, missing key, denied permission, etc.
        func error(_ message: String) {
            print("[\(name)] ERROR: \(message)")
            logger.error("\(message, privacy: .public)")
        }
    }
}
