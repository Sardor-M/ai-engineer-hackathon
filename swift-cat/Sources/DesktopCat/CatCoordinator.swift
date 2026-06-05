import AppKit
import Foundation

/// Bridges system events (frontmost app, cursor, Mail selection, click) to the
/// cat's visible state AND to the AI brain. Phases 1–3 cover state, brain,
/// voice, and listener; Phase 4a adds the visible UI — every brain output now
/// renders in a `SpeechBubble` and a `MicButton` in the cat window's
/// bottom-right corner replaces the `Cmd+Shift+L` hotkey (which still works as
/// a fallback). Phase 4b adds an `ActivePanel` to the left of the cat that
/// shows the *full* PDF summary or the Summary/Reply/Ask tabs for a selected
/// email; the speech bubble continues to surface only the first 1–2 sentences
/// for voice. Phase 4c adds a gear button beside the mic that toggles a
/// `SettingsOverlay` for voice on/off, default profile, auto-by-context, and
/// the mic-questions switch — all persisted through the existing `SettingsStore`.
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
    private var listenSessionID: Int = 0

    // UI (Phase 4a).
    private let bubble: SpeechBubble

    // UI (Phase 4b).
    private let panel: ActivePanel

    // UI (Phase 4c).
    private let settingsOverlay: SettingsOverlay

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
        listener: Listener,
        bubble: SpeechBubble,
        panel: ActivePanel,
        settingsOverlay: SettingsOverlay
    ) {
        self.catView = catView
        self.settings = settings
        self.memory = memory
        self.brain = brain
        self.voice = voice
        self.listener = listener
        self.bubble = bubble
        self.panel = panel
        self.settingsOverlay = settingsOverlay
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

        catView.micButton.onToggle = { [weak self] in self?.toggleListen() }

        catView.gearButton.onTap = { [weak self] in self?.settingsOverlay.toggle() }

        Log.cat.info("coordinator ready — bubble + mic + active panel + settings wired (Phase 4c)")
    }

    func stop() {
        frontmost.stop()
        cursor.stop()
        voice.stop()
        listener.stop()
        panel.hide()
        settingsOverlay.hide()
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
        Log.cat.info("frontmost mode=\(ctx.mode.rawValue) app=\(ctx.appName) title=\(trimmed)")

        switch ctx.mode {
        case .pdf:
            wakeUp()
            runPdfSummary()
        case .email:
            wakeUp()
            runEmailAnalysis()
        case .idle:
            // Drop any active-mode panel content when the user returns to a
            // generic foreground app. The bubble is left alone — it has its
            // own lifecycle tied to voice playback.
            panel.hide()
        }
    }

    private func handleCursor(_ trigger: CursorTrigger) {
        switch trigger {
        case .dwell(let p):
            Log.cat.info("cursor dwell at (\(Int(p.x)),\(Int(p.y)))")
        case .activity(let p):
            Log.cat.info("cursor activity near (\(Int(p.x)),\(Int(p.y)))")
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
                Log.cat.info("proactiveAssist: (silent)")
                return
            }
            Log.cat.info("proactiveAssist len=\(line.count) fp=\(fingerprint(line))")
            memory.append(Observation(
                at: Date(),
                description: nil,
                tag: "proactive",
                said: line
            ))
            await showAndSpeak(line, mode: .auto)
        } catch {
            Log.cat.error("proactiveAssist capture failed: \(error.localizedDescription)")
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
                    Log.cat.info("autonomous len=\(result.response.count) fp=\(fingerprint(result.response)) tag=\(result.tag)")
                }
                self.memory.append(Observation(
                    at: Date(),
                    description: description,
                    tag: result.tag.isEmpty ? nil : result.tag,
                    said: result.response.isEmpty ? nil : result.response
                ))
                if !result.response.isEmpty {
                    await self.showAndSpeak(result.response, mode: .auto)
                }
            } catch {
                Log.cat.error("observation capture failed: \(error.localizedDescription)")
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
                    Log.cat.info("pdf summary: (silent)")
                    return
                }
                Log.cat.info("pdf summary len=\(summary.count) fp=\(fingerprint(summary))")
                self.memory.append(Observation(
                    at: Date(),
                    description: "PDF page summarized",
                    tag: "pdf-summary",
                    said: summary
                ))
                // Full text goes to the panel; the bubble + voice only get
                // the first 1–2 sentences. Limit the spoken slice to ~280
                // chars so a long page doesn't become a long, monotone read.
                self.panel.show(pdf: summary)
                let spoken = self.firstSentences(of: summary, max: 280)
                await self.showAndSpeak(spoken, mode: .pdf)
            } catch {
                Log.cat.error("pdf capture failed: \(error.localizedDescription)")
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
                Log.cat.info("email: no selection")
                return
            }
            let dedupeKey = "\(mail.subject)|\(mail.sender)|\(mail.body.count)"
            if dedupeKey == self.lastEmailFingerprint {
                return  // same message — skip re-analyzing
            }
            self.lastEmailFingerprint = dedupeKey

            Log.cat.info("email selection: subjectLen=\(mail.subject.count) subjectFp=\(fingerprint(mail.subject)) from=\(mail.sender) bodyLen=\(mail.body.count)")
            let result = await self.brain.analyzeEmail(mail)
            if !result.summary.isEmpty {
                Log.cat.info("email summary len=\(result.summary.count) fp=\(fingerprint(result.summary))")
            }
            if !result.draftReply.isEmpty {
                Log.cat.info("email draft reply len=\(result.draftReply.count) fp=\(fingerprint(result.draftReply))")
            }
            if !result.clarifyingQuestion.isEmpty {
                Log.cat.info("email ask len=\(result.clarifyingQuestion.count) fp=\(fingerprint(result.clarifyingQuestion))")
            }
            self.memory.append(Observation(
                at: Date(),
                description: "Mail: \(mail.subject)",
                tag: "email-analyzed",
                said: result.summary.isEmpty ? nil : result.summary
            ))
            // Show every field the model returned in the panel; speak only
            // the summary so the user isn't read three paragraphs in a row.
            self.panel.show(email: result)
            if !result.summary.isEmpty {
                await self.showAndSpeak(result.summary, mode: .email)
            }
        }
    }

    // MARK: - Bubble + voice helper

    /// Show `displayed` in the speech bubble and speak `spoken` through Voice.
    /// When `spoken` is nil, the bubble text is also what gets spoken. The
    /// bubble hides when audio playback finishes; if voice is disabled or
    /// every engine refuses, the bubble auto-hides after a length-scaled
    /// timeout so it doesn't sit on screen forever.
    private func showAndSpeak(_ displayed: String, spoken: String? = nil, mode: VoiceMode) async {
        let trimmed = displayed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = bubble.show(trimmed)

        let speakText = (spoken ?? trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        let played = await voice.speak(
            speakText,
            mode: mode,
            settings: settings.current,
            onDone: { [weak self] in Task { @MainActor in self?.bubble.hide(id: id) } }
        )
        if played == nil {
            // No engine played — fall back to a soft timeout proportional to
            // the displayed text length (~70 ms/char, floor 2.5 s, ceiling 12 s).
            let estimate = max(2.5, min(12.0, Double(trimmed.count) * 0.07))
            bubble.hide(id: id, after: estimate)
        }
    }

    // MARK: - Helpers

    private func fingerprint(_ s: String) -> String { String(s.hashValue, radix: 16) }

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
            catView.micButton.setListening(false)
            return
        }

        // Barge-in: if the cat is speaking when the user wants to talk, stop.
        if voice.isSpeaking {
            voice.stop()
            bubble.hide()
        }

        guard !listenInFlight else { return }
        listenInFlight = true
        listenSessionID &+= 1
        let sessionID = listenSessionID
        wakeUp()
        catView.micButton.setListening(true)
        Log.listener.info("starting…")

        let callbacks = ListenerCallbacks(
            onPartial: { [weak self] text in
                guard let self, !text.isEmpty else { return }
                // Trim to a short prefix so a long partial doesn't spam logs.
                let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
                Log.listener.info("partial: \(preview)")
                self.wakeUp()
            },
            onFinal: { [weak self] text in
                guard let self, self.listenSessionID == sessionID else { return }
                self.listenInFlight = false
                self.catView.micButton.setListening(false)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    Log.listener.info("final: (empty)")
                    return
                }
                Log.listener.info("final: \(trimmed)")
                self.handleUserUtterance(trimmed)
            },
            onError: { warning in
                Log.listener.warn(warning)
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
            Log.cat.info("reply len=\(reply.count) fp=\(fingerprint(reply))")
            self.memory.append(Observation(
                at: Date(),
                description: nil,
                tag: "user-reply",
                said: reply
            ))
            await self.showAndSpeak(reply, mode: .auto)
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
