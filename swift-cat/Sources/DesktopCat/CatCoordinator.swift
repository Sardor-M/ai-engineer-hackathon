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

    // Voice (Phase 3b).
    private let voice: Voice

    // Listener (Phase 3c).
    private let listener: Listener
    private var hotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?
    private var listenInFlight = false

    // System integrations.
    private let frontmost = FrontmostWatcher()
    private let cursor = CursorMonitor()
    private let screen: ScreenCapturing = ShellScreenCapture()

    // Idle timing — when nothing's happened for a while, drift back to puddle.
    private var lastActiveAt = Date()
    private var idleTimer: Timer?
    private let puddleAfterSec: TimeInterval = 22

    // Autonomous observation loop. Matches AUTONOMOUS_MS in renderer.js (20s);
    // default to 60s on Swift to be gentler on quota during dev. Override with
    // CAT_OBSERVATION_INTERVAL_SEC env var when you want it chattier.
    private var observationTimer: Timer?
    private let observationIntervalSec: TimeInterval = {
        if let raw = ProcessInfo.processInfo.environment["CAT_OBSERVATION_INTERVAL_SEC"],
           let n = Double(raw), n >= 5
        {
            return n
        }
        return 60
    }()
    private var observationInFlight = false

    // Per-mode work guards — we don't want two PDF summaries fighting each other.
    private var pdfInFlight = false
    private var emailInFlight = false
    private var lastEmailFingerprint: String?

    // Click-to-proactive guard + cooldown. Without this, rapid clicks fan out
    // into N parallel API calls and exhaust provider quota in seconds (saw 8+
    // proactiveAssist calls in <30s during the first dev run).
    private var proactiveInFlight = false
    private var lastProactiveAt = Date.distantPast
    private let proactiveCooldownSec: TimeInterval = 4

    init(
        catView: CatView,
        settings: SettingsStore,
        memory: MemoryStore,
        brain: Brain,
        voice: Voice,
        listener: Listener
    ) {
        self.catView = catView
        self.settings = settings
        self.memory = memory
        self.brain = brain
        self.voice = voice
        self.listener = listener
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

        installListenerHotkey()

        print("[cat] coordinator ready — brain + voice + listener wired (Phase 3a-3c); UI surfaces pending Phase 4")
    }

    func stop() {
        frontmost.stop()
        cursor.stop()
        voice.stop()
        listener.stop()
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m) }
        hotkeyMonitor = nil
        if let lm = localHotkeyMonitor { NSEvent.removeMonitor(lm) }
        localHotkeyMonitor = nil
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

        // Debounce: drop the click if one is already running or if the last one
        // finished less than `proactiveCooldownSec` ago. Without this, rapid
        // clicks each fire their own capture + brain call.
        if proactiveInFlight { return }
        if Date().timeIntervalSince(lastProactiveAt) < proactiveCooldownSec { return }

        proactiveInFlight = true
        Task { [weak self] in
            await self?.runProactiveAssist()
            await MainActor.run {
                self?.proactiveInFlight = false
                self?.lastProactiveAt = Date()
            }
        }
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
            await voice.speak(line, mode: .auto, settings: settings.current)
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
                if !result.response.isEmpty {
                    await self.voice.speak(result.response, mode: .auto, settings: self.settings.current)
                }
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
                // Speak the first 1-2 sentences — the active panel (Phase 4)
                // will show the full text. Limit to ~280 chars so ElevenLabs
                // doesn't bill us for a long, monotone read.
                let spoken = self.firstSentences(of: summary, max: 280)
                await self.voice.speak(spoken, mode: .pdf, settings: self.settings.current)
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
            if !result.summary.isEmpty {
                await self.voice.speak(result.summary, mode: .email, settings: self.settings.current)
            }
        }
    }

    // MARK: - Helpers

    /// Returns the first 1-2 sentences of `s`, capped at `max` characters. Used
    /// when we want to *speak* a passage but show the full thing in a panel.
    private func firstSentences(of s: String, max: Int) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = nil
        var out = ""
        var sentenceCount = 0
        while !scanner.isAtEnd && sentenceCount < 2 && out.count < max {
            if let piece = scanner.scanUpToCharacters(from: CharacterSet(charactersIn: ".!?")) {
                out.append(piece)
            }
            if let punct = scanner.scanCharacters(from: CharacterSet(charactersIn: ".!?")) {
                out.append(punct)
                sentenceCount += 1
            }
        }
        let result = out.isEmpty ? trimmed : out
        return result.count > max ? String(result.prefix(max)) : result
    }

    // MARK: - Listener (Phase 3c)

    /// Global Cmd+Shift+L toggles the mic. Replaced by the mic button on the
    /// cat window in Phase 4. Requires Accessibility for the global monitor;
    /// when denied, the user can still get the same effect by activating the
    /// app and using the local-monitor path below.
    private func installListenerHotkey() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let isCmdShift = event.modifierFlags.intersection([.command, .shift]) == [.command, .shift]
            // 0x25 = "L" virtual key on US layouts. Hard-coded for now; Phase 4
            // exposes this in settings.
            guard isCmdShift, event.keyCode == 0x25 else { return }
            self.toggleListen()
        }

        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            Task { @MainActor in handler(event) }
        }

        // Local monitor as a fallback when the cat happens to be the active
        // app (rare with .accessory policy, but possible after a click).
        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handler(event)
            return event
        }
    }

    private func toggleListen() {
        if listener.isListening {
            listener.stop()
            listenInFlight = false
            return
        }

        // Barge-in: if the cat is speaking when the user wants to talk, stop.
        if voice.isSpeaking { voice.stop() }

        guard !listenInFlight else { return }
        listenInFlight = true
        wakeUp()
        print("[listener] starting…")

        let callbacks = ListenerCallbacks(
            onPartial: { [weak self] text in
                guard let self, !text.isEmpty else { return }
                // Trim to a short prefix so a long partial doesn't spam logs.
                let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
                print("[listener] partial:", preview)
                self.wakeUp()
            },
            onFinal: { [weak self] text in
                guard let self else { return }
                self.listenInFlight = false
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    print("[listener] final: (empty)")
                    return
                }
                print("[listener] final:", trimmed)
                self.handleUserUtterance(trimmed)
            },
            onError: { warning in
                print("[listener] warning:", warning)
            }
        )

        Task { [weak self] in
            await self?.listener.start(callbacks: callbacks)
        }
    }

    private func handleUserUtterance(_ text: String) {
        memory.append(Observation(
            at: Date(),
            description: "user said: \(text.prefix(80))",
            tag: "user-utterance",
            said: nil
        ))

        Task { [weak self] in
            guard let self else { return }
            let reply = await self.brain.replyToUser(text)
            if reply.isEmpty { return }
            print("[cat] reply:", reply)
            self.memory.append(Observation(
                at: Date(),
                description: nil,
                tag: "user-reply",
                said: reply
            ))
            await self.voice.speak(reply, mode: .auto, settings: self.settings.current)
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
