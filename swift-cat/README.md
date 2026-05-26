# DesktopCat (Swift)

Native macOS rewrite of the Electron cat. See [`../docs/SWIFT_REWRITE.md`](../docs/SWIFT_REWRITE.md) for the full 4-phase plan.

## Status

| Phase | Status | What it covers |
|---|---|---|
| 1 — Foundation | ✅ shipped | Window, sprite stack, drag, breath, crossfade |
| 2 — System integrations | ✅ shipped | FrontmostWatcher, MailReader, ScreenCapture, CursorMonitor, Permissions, Settings + Memory stores, .app bundling |
| 3a — Brain | ✅ this branch | OpenAI + Gemini dispatcher, five prompts ported verbatim, 60-min rate-limit cooldown, wired into click → proactive + 30s idle loop + PDF / email modes |
| 3b — Voice | ⏳ next | ElevenLabs TTS + AVSpeechSynthesizer fallback, profile auto-switch |
| 3c — Listener | ⏳ next | SFSpeechRecognizer on-device + Whisper fallback |
| 4 — UI polish | ⏳ later | Speech bubble, active panel, settings overlay, per-profile color + animation, walking cycle |

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

## Permissions (first run)

For full functionality, grant in System Settings → Privacy & Security:

- **Screen Recording** — for screen capture (Phase 3 vision calls).
- **Accessibility** — for the global cursor monitor (the timer-based fallback works without it, just less responsive).
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
    ├── Storage/
    │   ├── AppSupport.swift
    │   ├── Settings.swift
    │   └── Memory.swift
    └── Resources/
        ├── cat_puddle.png
        └── cat_awake.png
```

The Electron app at the repo root continues to work; this is purely additive until Phase 4 cutover.
