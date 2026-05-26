# Swift Rewrite Plan — 4 Phases

Native macOS rewrite of the Electron+JS cat. The Electron version stays
shippable while the Swift port grows in `swift-cat/` alongside it; we cut over
when Phase 4 lands.

---

## Why Swift, not Tauri or "stay on Electron"

- **Speech recognition.** `webkitSpeechRecognition` does not work in WKWebView
  (Tauri's webview engine). The cat's "talk to me" feature would have to route
  every utterance through paid Whisper. `SFSpeechRecognizer` is on-device,
  free, and offline for short prompts — a real win.
- **Always-on animation budget.** Core Animation drives sprite work on the GPU
  with much lower idle cost than CSS keyframes in a Chromium renderer. The cat
  is meant to live there all day; the Electron version's idle footprint is
  ~150 MB RAM and noticeable battery.
- **macOS-native everything.** `ScreenCaptureKit`, `NSAppleScript`,
  `NSEvent.addGlobalMonitorForEvents`, TCC permission flows,
  `NSWorkspace.frontmostApplication`, menu bar items, Spaces, dark-mode follow,
  sleep/wake — all first-class instead of shimmed.
- **Distribution.** ~5-10 MB DMG vs the current ~150 MB.

Trade-off accepted: macOS-only forever (no Windows/Linux path).

---

## Where the work lives

```
ai-engineer-hackathon/
├── (existing Electron app at the root — stays shippable)
└── swift-cat/                    ← new home for the Swift port
    ├── Package.swift
    ├── README.md
    └── Sources/DesktopCat/
        ├── main.swift            ← entry point
        ├── AppDelegate.swift
        ├── CatWindow.swift       ← borderless, transparent, always-on-top NSWindow
        ├── CatView.swift         ← NSView hosting the sprite CALayers
        ├── CatState.swift        ← sprite enum + state machine (filled in by phase)
        ├── ...                   ← grows per phase
        └── Resources/
            └── cat_*.png         ← copied from ../../../assets per phase
```

Build is plain SwiftPM: `cd swift-cat && swift build && swift run`. We upgrade
to a proper Xcode app bundle in Phase 2 when TCC permissions become necessary.

---

## Phase 1 — Foundation (window + sprite shell)

**Goal:** A transparent, always-on-top, draggable cat window appears at the
bottom-right of the primary display. One sprite breathes. Clicking it swaps to
a second sprite (proves the animation pipeline works).

**Deliverables**
- SwiftPM `Package.swift` (executable target, macOS 13+, AppKit + QuartzCore).
- `main.swift` — `NSApplication` boot with `.accessory` activation policy
  (no dock icon, no global menu bar).
- `AppDelegate.swift` — instantiates and shows the cat window.
- `CatWindow.swift` — borderless `NSWindow` with `isOpaque=false`,
  `backgroundColor=.clear`, `level=.floating`, `collectionBehavior` set to
  follow the user across Spaces.
- `CatView.swift` — `NSView` with `wantsLayer=true`; sprite stack of two
  `CALayer`s (puddle + awake) crossfaded via `CATransaction` opacity changes.
- `Resources/cat_puddle.png`, `Resources/cat_awake.png` (copied from `assets/`).
- Manual drag implementation via `mouseDown` / `mouseDragged` (we do not use
  `isMovableByWindowBackground` so we can distinguish click from drag).
- Looping breath animation via `CABasicAnimation` on `transform.scale`.

**Acceptance**
- `cd swift-cat && swift run` launches; a chibi cat appears at bottom-right,
  breathes, can be dragged anywhere with the mouse, and clicking it without
  dragging crossfades sprites.
- Cmd+Q exits cleanly.
- Binary size at `swift build -c release` < 5 MB.

---

## Phase 2 — System integrations

**Goal:** All the macOS plumbing the Electron version shells out for is now
native: frontmost-app detection, Mail.app message selection, screen capture,
global cursor polling, TCC permission flow.

**Deliverables**
- Convert SwiftPM executable to an Xcode-bundled app (Info.plist with
  `LSUIElement=true`, hardened runtime, codesigned for local dev).
  TCC needs a bundle; pure SwiftPM binaries get prompted with the wrong app
  name.
- `FrontmostWatcher.swift` — `NSWorkspace.shared.notificationCenter` observer
  for `didActivateApplicationNotification`. Falls back to a 1 s polling timer
  for the focused window title via `AXUIElement` (Accessibility API).
- `MailReader.swift` — `NSAppleScript` wrapping the existing Mail selection
  AppleScript. Runs off the main thread.
- `ScreenCapture.swift` — `ScreenCaptureKit` (macOS 13+) for full-display and
  cursor-region grabs. Shells to `screencapture -x` as a fallback if SCK is
  unavailable.
- `CursorMonitor.swift` — `NSEvent.addGlobalMonitorForEvents(matching:
  [.mouseMoved])` replaces the 500ms `screen.getCursorScreenPoint` poll. Same
  dwell + active-motion logic as the Electron version, ported as a small
  struct.
- `Permissions.swift` — pre-flight checks for Screen Recording, Accessibility,
  and Automation (Mail, System Events). Friendly first-run dialog that opens
  the right Settings pane on tap.
- `Settings.swift` + `Memory.swift` — `Codable` structs persisted to
  `~/Library/Application Support/DesktopCat/{settings,memory}.json`.

**Acceptance**
- App detects when the user switches to Preview / Mail / a browser with a PDF
  open within ~1 s, with no shell-out overhead.
- Cursor dwell and active-motion triggers fire on the same thresholds as the
  Electron version.
- Permission prompts appear once on first run; subsequent runs use cached
  approvals.

---

## Phase 3 — AI brain

**Goal:** Feature parity with the current `brain.js` — OpenAI primary, Gemini
fallback, ElevenLabs voice, Whisper transcription, plus native
`SFSpeechRecognizer` so the cat can listen without paying for Whisper.

**Deliverables**
- `Brain.swift` — protocol-oriented dispatcher. `ChatProvider` protocol with
  two implementations: `OpenAIChat` (URLSession, chat-completions API,
  JSON-mode + vision attachments) and `GeminiChat` (URLSession, REST API).
  Per-provider 429 backoff, same semantics as `brain.js`.
- `Prompts.swift` — the five prompts ported verbatim (PDF, EMAIL, USER_REPLY,
  MOUSE_QUESTION, PROACTIVE) plus the `recent_lines_already_said` dedup hook.
- `Voice.swift`:
  - `ElevenLabsTTS` (URLSession + `AVAudioPlayer`, profile picker, per-mode
    auto-switch).
  - `SystemTTS` fallback wrapping `AVSpeechSynthesizer` (replaces browser
    `speechSynthesis`).
- `Listener.swift`:
  - `SFSpeechRecognizer` for live mic input (on-device, free). Hooks into
    `AVAudioEngine`.
  - `WhisperClient` for audio bytes when on-device recognition is unavailable
    (locale not installed, etc.).
- `MemoryStore.swift` — append-only observations buffer (last 100), exposed
  to prompts as `recent_lines_already_said`. Replaces `memory.json` JSON
  shuffling in `renderer.js`.

**Acceptance**
- Click cat → `proactiveAssist` runs end-to-end (capture → vision LLM →
  bubble + TTS) in ≤ 3 s with a real `OPENAI_API_KEY`.
- Pull the OpenAI key, set `GEMINI_API_KEY`, repeat → still works (fallback).
- Tap the mic, speak a sentence → bubble shows transcribed text in ~500 ms
  without any network round-trip (SFSpeechRecognizer).
- ElevenLabs audio plays through `AVAudioPlayer`; profile change in settings
  is honored on the next utterance.

---

## Phase 4 — UI polish + interactions

**Goal:** Visual + interaction parity. Speech bubble, active panel for
PDF/email mode, settings overlay, profile color tinting, talking animation,
walking cycle, mic button — all native.

**Deliverables**
- `SpeechBubble.swift` — small `NSPanel` that floats over the cat. Borderless,
  rounded, fades in/out, has a tail. Layout via SwiftUI inside the panel.
- `ActivePanel.swift` — left-anchored SwiftUI view (Summary/Reply/Ask tabs for
  email mode, single body for PDF mode). Pinned to the cat window's left edge.
- `SettingsOverlay.swift` — SwiftUI `Form` with voice toggle, profile picker,
  auto-by-context switch, mic-question toggle.
- Sprite tinting per profile via `CIColorMatrix` filter on the sprite layer
  (replaces the CSS `--aura` halo). Each profile gets its own static color
  matrix and shadow tint.
- Per-profile breath animations via `CAKeyframeAnimation` — five distinct
  pacing/amplitude curves matching the existing `breathe-soft/curious/bright/
  low/whisper` keyframes.
- Talking animation: `CABasicAnimation` group bound to `AVAudioPlayer`'s
  `play`/`stop` callbacks. Replaces the `.talking` class toggle.
- Walking cycle: `CALayer.contents` alternates between `cat_walk1` and
  `cat_walk2` every 250 ms for 4.5 s on a random 6-12 min interval.
- Mic button: small `NSView` overlay on the cat window, pulse animation when
  listening.

**Acceptance**
- Visual diff with the Electron version is < 10 % (within profile color and
  animation feel).
- Click on the cat with PDF open in Preview produces the same outcome:
  summary in the active panel + first sentence spoken in the chosen voice.
- Idle RAM: < 50 MB resident (vs Electron's ~150 MB).
- Cold-start: window visible in < 300 ms.

---

## Migration strategy

- **Phase 1-3 run alongside Electron.** The two apps share `assets/` PNGs and
  the prompts (we keep `cat_prompt.txt` at the root; Swift reads it the same
  way `brain.js` does). They write to the same `memory.json` location so
  history carries over.
- **At Phase 4 cutover:** mark the Electron entry points (`npm start`,
  `package.json`) as deprecated; ship a code-signed DMG of the Swift app.
- **Rollback:** if Phase 4 takes longer than expected, Phase 1-3 deliver
  partial value alone (e.g. a Phase 3 binary already replaces `brain.js`).
  Each phase is independently shippable.

## Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| `SFSpeechRecognizer` locale not installed on user's machine | Medium | Fall back to `WhisperClient` automatically; show a one-time hint to add the locale in System Settings. |
| `ScreenCaptureKit` denied | High on first run | Pre-flight check in Phase 2; open the right System Settings pane and friendly explanation. |
| AppleScript Automation denial for Mail | Medium | Cat works without Mail mode; surface a single-line status in the settings overlay. |
| Sandboxing complications for App Store | Low (we're not shipping there) | Ignore for v1. |
| Async/await + AppKit threading | Low | Audit `@MainActor` annotations in Phase 2 review. |

## Out of scope for this rewrite

- Windows / Linux ports — explicitly rejected, this is macOS-native.
- iCloud sync of memory.json — not in the original.
- Notifications / dock badge — the cat is silent unless she speaks.
