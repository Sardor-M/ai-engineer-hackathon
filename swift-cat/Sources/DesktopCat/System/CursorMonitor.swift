import AppKit
import Foundation

/// Triggers fired when the user's mouse satisfies a condition we care about.
enum CursorTrigger: Sendable {
    case dwell(at: CGPoint)      // cursor sat still ≥ dwellTriggerSec
    case activity(at: CGPoint)   // cursor covered ≥ activeDistancePx within activeWindowSec
}

/// Watches the system cursor for dwell and active-motion events. Thresholds
/// are tuned to match the Electron version exactly so behavior carries over.
///
/// Permission notes:
/// - `NSEvent.mouseLocation` reads the cursor without any permission.
/// - `NSEvent.addGlobalMonitorForEvents` *does* require Accessibility, but
///   the timer-based poll below covers us when permission is missing.
@MainActor
final class CursorMonitor {
    var onTrigger: ((CursorTrigger) -> Void)?

    // Thresholds — see /docs/SWIFT_REWRITE.md.
    private let dwellTriggerSec: TimeInterval = 1.2
    private let questionCooldownSec: TimeInterval = 10.0
    private let minMoveFromLastQ: CGFloat = 80
    private let activeWindowSec: TimeInterval = 8.0
    private let activeDistancePx: CGFloat = 1500
    private let activeCooldownSec: TimeInterval = 14.0
    private let pollIntervalSec: TimeInterval = 0.5

    private var monitor: Any?
    private var pollTimer: Timer?

    private var lastSample = CGPoint.zero
    private var dwellStartedAt = Date.distantPast
    private var lastTriggerAt = Date.distantPast
    private var lastTriggerPos = CGPoint(x: -1e9, y: -1e9)
    private var lastActivityTriggerAt = Date.distantPast
    private var recentSamples: [(t: Date, p: CGPoint)] = []

    func start() {
        // Global monitor as an optimization — fires only when Accessibility is
        // granted. Silent no-op otherwise.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        lastSample = NSEvent.mouseLocation
        dwellStartedAt = Date()
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func sample() {
        let now = Date()
        let p = NSEvent.mouseLocation

        recentSamples.append((now, p))
        recentSamples.removeAll { now.timeIntervalSince($0.t) > activeWindowSec }

        let movedNow = manhattan(p, lastSample) > 4
        if movedNow {
            lastSample = p
            dwellStartedAt = now
        }

        let dwell = now.timeIntervalSince(dwellStartedAt)
        let sinceQ = now.timeIntervalSince(lastTriggerAt)
        let movedFromLastQ = manhattan(p, lastTriggerPos)

        // Branch A — dwell.
        if !movedNow
            && dwell > dwellTriggerSec
            && sinceQ > questionCooldownSec
            && movedFromLastQ > minMoveFromLastQ
        {
            fire(.dwell(at: p), at: now)
            return
        }

        // Branch B — active motion.
        if movedNow {
            let covered = totalManhattan(recentSamples)
            let sinceActive = now.timeIntervalSince(lastActivityTriggerAt)
            if covered > activeDistancePx
                && sinceActive > activeCooldownSec
                && sinceQ > questionCooldownSec
            {
                lastActivityTriggerAt = now
                fire(.activity(at: p), at: now)
            }
        }
    }

    private func fire(_ trigger: CursorTrigger, at time: Date) {
        lastTriggerAt = time
        switch trigger {
        case .dwell(let p), .activity(let p):
            lastTriggerPos = p
        }
        onTrigger?(trigger)
    }

    private func manhattan(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private func totalManhattan(_ samples: [(t: Date, p: CGPoint)]) -> CGFloat {
        guard samples.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 1..<samples.count {
            total += manhattan(samples[i].p, samples[i - 1].p)
        }
        return total
    }
}
