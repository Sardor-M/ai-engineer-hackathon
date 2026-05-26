# DesktopCat (Swift)

Native macOS rewrite of the Electron cat. See [`../docs/SWIFT_REWRITE.md`](../docs/SWIFT_REWRITE.md) for the full 4-phase plan.

## Status

| Phase | Status | What it covers |
|---|---|---|
| 1 — Foundation | ✅ shipped | Window, sprite stack, drag, breath, crossfade |
| 2 — System integrations | ✅ shipped | FrontmostWatcher, MailReader, ScreenCapture, CursorMonitor, Permissions, Settings + Memory stores, .app bundling |
| 3a — Brain | ✅ shipped | OpenAI + Gemini dispatcher, five prompts ported verbatim, 60-min rate-limit cooldown, wired into click → proactive + 60s idle loop + PDF / email modes |
| 3b — Voice | ✅ shipped | ElevenLabs TTS via AVAudioPlayer, AVSpeechSynthesizer fallback, VoicePicker auto-switch by mode + night hours, spoken after every brain output |
| 3c — Listener | ✅ this branch | SFSpeechRecognizer on-device + Whisper fallback, Cmd+Shift+L toggle, transcript → reply → speak loop |
| 4 — UI polish | ⏳ next | Speech bubble, active panel, settings overlay, per-profile color + animation, walking cycle |

## Build & run

```bash
cd swift-cat
swift run               # debug build + launch
make release            # release build
make bundle             # wrap into build/DesktopCat.app (stable bundle id for TCC)
make open-bundle        # run the bundled .app — needed for persistent permissions
```

Quit with **Cmd+Q**.

## Phase 2 — what works now

When you `swift run`, the terminal logs everything the cat sees:

```
[cat] permission Screen Recording: not granted (will prompt on first use)
[cat] permission Accessibility:   not granted (will prompt on first use)
[cat] permission Automation:      granted
[cat] coordinator ready — sprite reactions live, brain stubs pending Phase 3
[cat] frontmost mode=pdf   app=Preview      title=paper.pdf
[cat] cursor activity near (1240, 360)
[cat] frontmost mode=email app=Mail         title=Inbox
[cat] mail selection: subject="hello" from=alice@x.com bodyLen=412
[cat] clicked — would trigger proactiveAssist in Phase 3
[cat] captured 245 kb (capture pipeline working)
```

The cat sprite physically reacts:
- Opens a PDF in Preview → cat crossfades to **awake**
- Selects a Mail message → reads it via AppleScript, logs subject/sender/body length
- Wave the cursor around → cat wakes
- Cursor sits still ≥ 1.2 s anywhere new → dwell trigger
- Cursor covers ≥ 1500 px in 8 s → active-motion trigger
- ~22 s of no activity → cat settles back to puddle

Click the cat → runs the capture pipeline end-to-end (prints capture byte size) so you can confirm `screencapture` is granted before Phase 3 lands.

## Phase 3a — what works now

With `OPENAI_API_KEY` (and/or `GEMINI_API_KEY`) in your environment, the brain is now live behind the same triggers — outputs go to stdout pending the Phase 4 UI:

```
[cat] frontmost mode=pdf  app=Preview  title=paper.pdf
[cat] pdf summary: ah — they're showing that masked tokens still beat a no-pretraining baseline on the smaller corpus…
[cat] clicked — would trigger proactiveAssist  (replaced)
[cat] proactiveAssist: hm, three tabs of stack overflow. it's that kind of bug.
[cat] autonomous: the page is patient. so is the chair. (tag=writing-pause)
[cat] email summary: alice is asking whether tuesday still works for the demo.
[cat] email draft reply: hi alice, tuesday works on my end…
[cat] email ask: have we confirmed the meeting room yet?
```

Provider selection: tries OpenAI first; falls through to Gemini on empty / 429. A 429 from either provider freezes only that provider for 60 minutes (matches the Electron behavior). Pull `OPENAI_API_KEY` and set `GEMINI_API_KEY` to verify the fallback path.

## Phase 3b — what works now

With `ELEVENLABS_API_KEY` in your environment, every brain output is now spoken aloud through `AVAudioPlayer`. Voice profile auto-switches by mode (PDF → low / studious, Mail → soft, idle → user default, hours 22–06 → whisper). Pull `ELEVENLABS_API_KEY` and you'll fall through to `AVSpeechSynthesizer` — voice loses character but the cat keeps talking.

```
[cat] proactiveAssist: hm, three tabs of stack overflow. it's that kind of bug.
[voice] elevenlabs → playing (profile=soft)
[cat] pdf summary: oh — they're claiming masked tokens still beat the no-pretraining baseline…
[voice] elevenlabs → playing (profile=low)
```

Env knobs added on this branch:
- `CAT_OBSERVATION_INTERVAL_SEC` — autonomous loop interval (default 60s, min 5).
- `ELEVENLABS_API_KEY` — when unset, falls through to `AVSpeechSynthesizer`.

Click cooldown is 4s — rapid clicks no longer fan out into N parallel API calls.

## Phase 3c — what works now

Press **Cmd+Shift+L** anywhere on the system to toggle the mic. The cat listens
through `AVAudioEngine` and transcribes via on-device `SFSpeechRecognizer`
(free, no network round-trip). When the locale isn't installed, falls back to
Whisper at OpenAI. On a final transcript she calls `Brain.replyToUser` and
speaks the answer through `Voice`. Press the hotkey again to stop early — she
also auto-stops after 60 s when using the Whisper path.

```
[listener] starting…
[listener] partial: how's my work looking
[listener] final: how's my work looking
[cat] reply: mm. you've been at that diff for a while — take a sip of water.
[voice] elevenlabs → playing (profile=soft)
```

Barge-in works: starting the mic while the cat is talking stops the current
utterance.

Env knobs added on this branch:
- `WHISPER_API_KEY` — explicit override for the Whisper fallback. Falls back to `OPENAI_API_KEY` when unset, since OpenAI keys cover both endpoints.

## Permissions (first run)

For full functionality, grant in System Settings → Privacy & Security:

- **Screen Recording** — for screen capture (Phase 3 vision calls).
- **Accessibility** — for the global cursor monitor and Cmd+Shift+L hotkey (a local monitor handles the case when the cat is the focused app).
- **Microphone** — for the mic input (Phase 3c). Prompted on first listen.
- **Speech Recognition** — for on-device transcription (Phase 3c). Prompted on first listen.
- **Automation → Mail / System Events** — granted on first AppleScript use.

The bundled `.app` (from `make bundle`) is the path TCC remembers; `swift run` rebuilds the binary at a new path each time, so re-grants get awkward. Once you need stable permissions, use the bundle.

## Project layout

```
swift-cat/
├── Package.swift
├── Makefile                 ← build / release / bundle / open-bundle / clean
├── README.md
└── Sources/DesktopCat/
    ├── main.swift           ← NSApplication entry, .accessory policy
    ├── AppDelegate.swift    ← boots stores, window, coordinator
    ├── CatWindow.swift      ← borderless transparent NSWindow
    ├── CatView.swift        ← sprite layer stack, drag + onClick callback
    ├── CatState.swift       ← sprite enum
    ├── CatMode.swift        ← idle / pdf / email
    ├── CatCoordinator.swift ← bridges system events → cat state
    ├── System/
    │   ├── FrontmostWatcher.swift
    │   ├── MailReader.swift
    │   ├── ScreenCapture.swift
    │   ├── CursorMonitor.swift
    │   └── Permissions.swift
    ├── Brain/
    │   ├── Brain.swift          ← provider-agnostic dispatcher
    │   ├── ChatProvider.swift
    │   ├── OpenAIChat.swift
    │   ├── GeminiChat.swift
    │   ├── RateLimiter.swift
    │   └── Prompts.swift
    ├── Voice/
    │   ├── Voice.swift          ← TTS dispatcher
    │   ├── TTSEngine.swift
    │   ├── ElevenLabsTTS.swift
    │   ├── SystemTTS.swift
    │   └── VoicePicker.swift
    ├── Listener/
    │   ├── Listener.swift       ← STT dispatcher
    │   ├── ListenerEngine.swift
    │   ├── SpeechListener.swift ← SFSpeechRecognizer (on-device)
    │   └── WhisperListener.swift
    ├── Storage/
    │   ├── AppSupport.swift
    │   ├── Settings.swift
    │   └── Memory.swift
    └── Resources/
        ├── cat_puddle.png
        └── cat_awake.png
```

The Electron app at the repo root continues to work; this is purely additive until Phase 4 cutover.
