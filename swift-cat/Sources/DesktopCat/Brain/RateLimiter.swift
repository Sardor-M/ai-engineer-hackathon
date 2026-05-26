import Foundation

/// Per-provider 60-minute cooldown after a 429 / quota error. Matches the
/// `openaiBlockedUntil` / `geminiBlockedUntil` pair in `brain.js`.
///
/// Actor isolation lets providers be `Sendable` and `async`-friendly while
/// the state itself remains thread-safe — there is no UI dependency here so
/// `actor` is a better fit than `@MainActor`.
actor RateLimiter {
    static let shared = RateLimiter()

    private var blockedUntil: [String: Date] = [:]
    private let cooldown: TimeInterval = 60 * 60   // 60 min, matches brain.js

    private init() {}

    /// Returns true if `provider` is currently blocked.
    func isBlocked(_ provider: String) -> Bool {
        guard let until = blockedUntil[provider] else { return false }
        if Date() >= until {
            blockedUntil.removeValue(forKey: provider)
            return false
        }
        return true
    }

    /// Marks `provider` blocked for 60 minutes. Idempotent — a second 429
    /// inside the cooldown window just refreshes the clock.
    func markBlocked(_ provider: String, reason: String) {
        blockedUntil[provider] = Date().addingTimeInterval(cooldown)
        print("[brain] \(provider) rate-limit — backing off 60 min: \(reason.prefix(120))")
    }

    /// Debug snapshot of who's blocked and for how much longer (seconds).
    func snapshot() -> [String: TimeInterval] {
        let now = Date()
        return blockedUntil.compactMapValues { until in
            let remaining = until.timeIntervalSince(now)
            return remaining > 0 ? remaining : nil
        }
    }
}
