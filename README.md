# The Cat

A small, round, black cat that lives on your desktop. She watches quietly, occasionally says something brief, and remembers what she's seen across sessions.

She is **not** a productivity assistant. She's a presence — silent by default, oblique when she does speak, and increasingly familiar over time.

When she notices you reading a PDF or replying to an email, she shifts into an active "context copilot" mode and offers a short summary or a draft reply.

---

## Features

- **Transparent, frameless, always-on-top window** that floats over your desktop and can be dragged anywhere on the screen.
- **Seven-sprite state machine** — puddle (resting), awake, sleep, walk1/walk2 (walking cycle), annoyed, ball-play — with idle breathing, perk, tilt, and shake animations.
- **Two parallel cognition loops:**
  - *Autonomous loop* (~30 s): screenshots the screen, asks Gemini Flash for a one-line description, then asks the cat-personality model whether to say anything. Most of the time, she stays silent.
  - *Active loop* (~4 s): polls the foreground macOS app + window. If you're reading a PDF or have a Mail message selected, the glass panel opens with a context-aware summary, draft reply, or clarifying question.
- **Persistent memory** in `memory.json` — a rolling window of up to 100 observations carries across sessions.
- **Optional voice** via ElevenLabs. Five voice profiles (soft, curious, bright, low, whisper) and a "match voice to work type" toggle that picks profiles based on context (PDF, email, late-night).
- **Settings panel** to toggle voice, pick a profile, and enable/disable context-aware voice switching. Settings persist in `settings.json`.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Electron app (main.js)                                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ IPC handlers:                                              │  │
│  │   capture-screen     → screencapture(1) → PNG buffer       │  │
│  │   cat:getContext     → osascript → frontmost app + Mail    │  │
│  │   cat:capturePrimary → screencapture(1) → base64           │  │
│  │   cat:summarizePdf   → brain.summarizePdfImage             │  │
│  │   cat:analyzeEmail   → brain.analyzeEmail                  │  │
│  │   cat:speak          → ElevenLabs TTS → mp3 base64         │  │
│  │   cat:get/setSettings, read/write-memory                   │  │
│  └────────────────────────────────────────────────────────────┘  │
│           ▲                                          ▲           │
│           │ contextBridge (preload.js)               │           │
│           ▼                                          │           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Renderer (renderer.js + index.html + styles.css)           │  │
│  │   • sprite manager + animation scheduler                   │  │
│  │   • autonomousTick (30 s)                                  │  │
│  │   • activeTick (4 s) → glass panel (Summary/Reply/Ask)     │  │
│  │   • speech bubble + voice playback                         │  │
│  │   • settings overlay                                       │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                          │
                          ▼
        ┌──────────────────────────────────┐
        │ brain.js                         │
        │   describeScreen      (Gemini)   │
        │   getCatResponse      (Gemini)   │
        │   summarizePdfImage   (Gemini)   │
        │   analyzeEmail        (Gemini)   │
        │   pickVoiceProfile  (heuristic)  │
        └──────────────────────────────────┘
```

Cost discipline: a cheap vision call describes the screen, the personality model returns an empty string most of the time, and capture-skipping by context fingerprint avoids redundant calls when nothing has changed.

---

## Setup

### Prerequisites

- **macOS** (the active context-copilot mode uses AppleScript and `screencapture`).
- **Node.js 18+** and npm.
- A **Gemini API key** (free tier is fine). [Get one here](https://aistudio.google.com/apikey).
- *(Optional)* an **ElevenLabs API key** for voice. Without it, the cat is text-only.

### Install

```bash
npm install
cp .env.example .env
# edit .env and add GEMINI_API_KEY (and optionally ELEVENLABS_API_KEY)
npm start
```

### macOS permissions (first run)

The first time you launch, macOS will prompt for two permissions. Both are required for the active mode to work:

1. **Screen Recording** — System Settings → Privacy & Security → Screen Recording → enable for your terminal (or for Electron itself once it appears in the list). Required for `screencapture`.
2. **Automation** — accept the prompts that ask permission to control "System Events" and "Mail". Required for detecting the foreground app and reading the selected email.

If you grant Screen Recording mid-session, **fully quit and relaunch** the terminal; macOS only re-reads TCC permissions on process startup.

---

## Configuration

### Environment variables (`.env`)

| Variable | Required | Purpose |
| --- | --- | --- |
| `GEMINI_API_KEY` | yes | Vision + text via `gemini-2.5-flash`. |
| `ELEVENLABS_API_KEY` | no | Voice output. If absent, voice is disabled. |

### Settings (`settings.json`, written by the app)

| Field | Default | Purpose |
| --- | --- | --- |
| `voiceEnabled` | `false` | Master voice toggle. |
| `voiceProfile` | `"soft"` | Default ElevenLabs profile (`soft` / `curious` / `bright` / `low` / `whisper`). |
| `autoVoiceByContext` | `true` | When on, profile is picked from work type + time of day (e.g. `whisper` after 22:00, `low` for PDFs, `soft` for email). |

Open the in-app settings panel via the gear icon on the cat.

---

## Project structure

```
.
├── main.js              # Electron main process, IPC handlers, AppleScript bridges
├── preload.js           # contextBridge: exposes `window.desktopCat` to renderer
├── renderer.js          # sprite state machine, both ticks, panel + voice UI
├── brain.js             # Gemini calls + voice profile selection
├── cat_prompt.txt       # personality prompt (system instruction)
├── index.html           # cat sprites + glass panel + settings overlay
├── styles.css           # all visual states + keyframe animations
├── assets/              # cat sprites used at runtime (PNG)
├── cat_images/          # source sprites in PNG + SVG (asset library)
└── docs/
    └── execution.md     # hackathon execution plan & team coordination
```

Files written at runtime (gitignored): `.env`, `memory.json`, `settings.json`, `journal.txt`.

---

## Troubleshooting

**`Error occurred in handler for 'capture-screen': Failed to get sources.`**
The terminal (or Electron) doesn't have Screen Recording permission. Open System Settings → Privacy & Security → Screen Recording, enable the entry for your terminal app, then quit and relaunch. The capture path now uses `screencapture(1)`, so as long as the CLI permission is granted, it will work.

**The active panel never opens for PDFs or email.**
Confirm the foreground app is one of: Preview, Adobe Acrobat, a browser viewing a `.pdf` URL, or Mail.app with a message *actually selected*. Open Console.app and look for `[cat] mode=...` log lines from `npm start` — they tell you what mode the classifier picked.

**The cat says nothing for long stretches.**
That's intended. The personality prompt instructs her to return an empty string most of the time. Click the cat to force a tick.

**Voice is silent even though `voiceEnabled` is true.**
Check the settings panel — if the warning reads "no ELEVENLABS_API_KEY in .env", add the key to `.env` and restart.

---

## Documentation

- [`docs/execution.md`](docs/execution.md) — hackathon execution plan, team coordination, and the original 3-hour scope decisions.

---

## License

MIT.
