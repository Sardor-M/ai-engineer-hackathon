import AppKit
import Foundation

/// Bridges system events (frontmost app, cursor, Mail selection, click) to the
/// cat's visible state AND to the AI brain. Phase 2 proved the wiring; Phase 3a
/// adds the brain calls — click → proactiveAssist, 30s idle observation loop,
/// PDF mode summary, Mail mode three-part analysis. UI surfacing (speech bubble,
/// active panel) lands in Phase 4; for now the brain outputs go to stdout so
/// you can see them.
@MainActor
final class CatCoordinator {

    // Visible state target.
    private let catView: CatView

    // Storage.
    private let settings: SettingsStore
    private let memory: MemoryStore

    // Brain.
    private let brain: Brain

    // System integrations.
    private let frontmost = FrontmostWatcher()
    private let cursor = CursorMonitor()
    private let screen: ScreenCapturing = ShellScreenCapture()

    // Idle timing — when nothing's happened for a while, drift back to puddle.
    private var lastActiveAt = Date()
    private var idleTimer: Timer?
    private let puddleAfterSec: TimeInterval = 22

    // Autonomous observation loop. Matches AUTONOMOUS_MS in renderer.js (20s);
    // we use 30s on Swift to be gentler on quota during dev.
    private var observationTimer: Timer?
    private let observationIntervalSec: TimeInterval = 30
    private var observationInFlight = false

    // Per-mode work guards — we don't want two PDF summaries fighting each other.
    private var pdfInFlight = false
    private var emailInFlight = false
    private var lastEmailFingerprint: String?

    init(catView: CatView, settings: SettingsStore, memory: MemoryStore, brain: Brain) {
        self.catView = catView
        self.settings = settings
        self.memory = memory
        self.brain = brain
    }

    func start() {
        Permissions.preflight()

        catView.onClick = { [weak self] in self?.handleCatClick() }

        frontmost.onChange = { [weak self] ctx in self?.handleFrontmost(ctx) }
        frontmost.start()

        cursor.onTrigger = { [weak self] trigger in self?.handleCursor(trigger) }
        cursor.start()

        idleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }

        observationTimer = Timer.scheduledTimer(withTimeInterval: observationIntervalSec, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runObservationTick() }
        }

        print("[cat] coordinator ready — brain wired (Phase 3a); UI surfaces pending Phase 4")
    }

    func stop() {
        frontmost.stop()
        cursor.stop()
        idleTimer?.invalidate()
        idleTimer = nil
        observationTimer?.invalidate()
        observationTimer = nil
    }

    // MARK: - Event handlers

    private func handleFrontmost(_ ctx: FrontmostContext) {
        let trimmed = ctx.title?.prefix(60).description ?? ""
        print("[cat] frontmost mode=\(ctx.mode.rawValue) app=\(ctx.appName) title=\(trimmed)")

        switch ctx.mode {
        case .pdf:
            wakeUp()
            runPdfSummary()
        case .email:
            wakeUp()
            runEmailAnalysis()
        case .idle:
            break
        }
    }

    private func handleCursor(_ trigger: CursorTrigger) {
        switch trigger {
        case .dwell(let p):
            print("[cat] cursor dwell at (\(Int(p.x)),\(Int(p.y)))")
        case .activity(let p):
            print("[cat] cursor activity near (\(Int(p.x)),\(Int(p.y)))")
        }
        wakeUp()
        // askMouseQuestion (region capture → Brain.askMouseQuestion) is wired
        // in Phase 3b alongside Voice/Listener so the question can actually be
        // spoken.
    }

    private func handleCatClick() {
        wakeUp()
        Task { [weak self] in await self?.runProactiveAssist() }
    }

    // MARK: - Brain calls

    private func runProactiveAssist() async {
        do {
            let image = try await screen.capturePrimary()
            let memorySnapshot = memory.current
            let line = await brain.proactiveAssist(image, memory: memorySnapshot)
            if line.isEmpty {
                print("[cat] proactiveAssist: (silent)")
                return
            }
            print("[cat] proactiveAssist:", line)
            memory.append(Observation(
                at: Date(),
                description: nil,
                tag: "proactive",
                said: line
            ))
        } catch {
            print("[cat] proactiveAssist capture failed:", error.localizedDescription)
        }
    }

    private func runObservationTick() {
        guard !observationInFlight else { return }
        observationInFlight = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.observationInFlight = false } }
            guard let self else { return }
            do {
                let image = try await self.screen.capturePrimary()
                let description = await self.brain.describeScreen(image)
                let snapshot = self.memory.current
                let result = await self.brain.getCatResponse(description: description, memory: snapshot)
                if !result.response.isEmpty {
                    print("[cat] autonomous:", result.response, "(tag=\(result.tag))")
                }
                self.memory.append(Observation(
                    at: Date(),
                    description: description,
                    tag: result.tag.isEmpty ? nil : result.tag,
                    said: result.response.isEmpty ? nil : result.response
                ))
            } catch {
                print("[cat] observation capture failed:", error.localizedDescription)
            }
        }
    }

    private func runPdfSummary() {
        guard !pdfInFlight else { return }
        pdfInFlight = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.pdfInFlight = false } }
            guard let self else { return }
            do {
                let image = try await self.screen.capturePrimary()
                let summary = await self.brain.summarizePdfImage(image)
                if summary.isEmpty {
                    print("[cat] pdf summary: (silent)")
                    return
                }
                print("[cat] pdf summary:", summary)
                self.memory.append(Observation(
                    at: Date(),
                    description: "PDF page summarized",
                    tag: "pdf-summary",
                    said: summary
                ))
            } catch {
                print("[cat] pdf capture failed:", error.localizedDescription)
            }
        }
    }

    private func runEmailAnalysis() {
        guard !emailInFlight else { return }
        emailInFlight = true
        Task { [weak self] in
            defer { Task { @MainActor in self?.emailInFlight = false } }
            guard let self else { return }
            guard let mail = await MailReader.readSelected() else {
                print("[cat] email: no selection")
                return
            }
            let fingerprint = "\(mail.subject)|\(mail.sender)|\(mail.body.count)"
            if fingerprint == self.lastEmailFingerprint {
                return  // same message — skip re-analyzing
            }
            self.lastEmailFingerprint = fingerprint

            print("[cat] email selection: subject=\"\(mail.subject)\" from=\(mail.sender) bodyLen=\(mail.body.count)")
            let result = await self.brain.analyzeEmail(mail)
            if !result.summary.isEmpty {
                print("[cat] email summary:", result.summary)
            }
            if !result.draftReply.isEmpty {
                print("[cat] email draft reply:", result.draftReply.prefix(200), "…")
            }
            if !result.clarifyingQuestion.isEmpty {
                print("[cat] email ask:", result.clarifyingQuestion)
            }
            self.memory.append(Observation(
                at: Date(),
                description: "Mail: \(mail.subject)",
                tag: "email-analyzed",
                said: result.summary.isEmpty ? nil : result.summary
            ))
        }
    }

    // MARK: - Idle / wake helpers

    private func wakeUp() {
        lastActiveAt = Date()
        catView.setState(.awake)
    }

    private func checkIdle() {
        guard Date().timeIntervalSince(lastActiveAt) > puddleAfterSec else { return }
        catView.setState(.puddle)
    }
}
