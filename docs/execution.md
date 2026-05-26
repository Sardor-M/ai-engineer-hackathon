# Team Execution Plan: 3 People, 3 Hours, 2pm → 5pm

> Late start, no code, three builders, hard 5pm deadline. This plan is brutal about scope. Read it once, assign roles, start.

---

## What We're Building

A small, round, black cat with soft yellow eyes who lives on your desktop. She sits there. She watches what you're doing. Once in a while — *only* once in a while — she says something quiet and slightly oblique about it. Then she goes back to sitting.

She is not an assistant. She does not help you take notes, schedule your day, or play your music. She is a **presence** — a character who shares your screen and has opinions about you that she mostly keeps to herself. Over time, she remembers things. By session three, she greets you like someone who knows you.

**Why this idea, in one paragraph:** every AI demo in 2026 is a desperately helpful agent that wants to do things for you. The cat is the opposite — she's an AI that's allowed to be *quiet*. Her whole personality is restraint. The technical novelty is in *what she doesn't do*: skip API calls when the screen hasn't changed, stay silent most of the time, use the cheapest model that gets the job done at every step. The emotional novelty is that she's a character, not a tool — small, mysterious, slightly old, fond of you in a way she'd never say directly.

### The character

- **Look:** small, round, simple black silhouette. Two soft yellow dot eyes. No mouth, no whiskers, no accessories. Sits patiently. Becomes a flat puddle when she sleeps.
- **Voice:** rare, brief, oblique. Speaks the way old things speak — small, plain, settled. No exclamation marks, no emoji, no internet cadence. "The hour is late" rather than "you should sleep."
- **Behavior:** silent by default. Speaks only when something genuinely catches her attention — usually less than once a minute. Has unexplained memories of "kitchens she's known" and "winters she half-remembers." Never explains herself.

### How it works (technical shape)

A two-stage AI pipeline running in an Electron desktop app on Windows 11:

1. **Eyes (cheap):** every ~30 seconds, take a screenshot, downsize it, send it to **Gemini's vision model** which returns a one-sentence description of what's happening.
2. **Voice (expensive):** feed that description plus past memories into **GPT-5.5 (or Claude)** with the cat's personality prompt. Most of the time, the model returns an empty string and nothing happens. Occasionally, it returns a line — that becomes a speech bubble above the cat.
3. **Memory:** notable observations get appended to a `memory.json` file that persists between sessions. Each new run, the cat has context on past sessions.
4. **Efficiency layer:** screenshots are hashed for change detection — if the screen looks the same as last time, skip the API call entirely. Capture frequency adapts to user activity (active/slow/idle/asleep). This is the **Adaption Labs track angle**: the cheapest tool that gets the job done at every step.

### Why this fits the hackathon

- **Adaption Labs track ($1.5k):** the entire architecture demonstrates their thesis — adaptive frequency, change detection, two-tier model routing. The cat literally adapts to you.
- **Best use of GPT-5.5:** the personality work is the hard part. Generating *restraint* from an LLM (silence as default) is a genuine reasoning challenge.
- **Best use of GPT Image 2:** the cat's sprites are AI-generated; can also extend to her generating little drawings or "postcards" as the wow moment.
- **Main prize:** memorable, emotional, demos in 90 seconds, and ships in one screen.

### What we are NOT building (locked — do not propose adding these)

- Voice / audio (no ElevenLabs, no Gemini Live)
- Customizable den or environment
- Note-taking, reminders, music control, calendar
- Webcam reactivity (tempting, do not)
- Multiple cats interacting
- Local privacy/filtering model

Each of these is a real feature. Each would also break the 5-hour timeline. They go on the "future work" slide of the pitch deck. They do not get built today.

### What "done" looks like at 7pm

A judge walks up. We open the laptop. The cat is sitting there, blinking occasionally, sparkles drifting around her. The judge watches for 20 seconds — she stays silent. Someone opens Twitter on the laptop; 30 seconds later the cat says "still that little blue place, hm" in a speech bubble. We close the app. A `journal.txt` file appears in the folder. We open it. The cat has written one sentence to herself about today.

That's the whole demo. 90 seconds. If we ship that, we win something.

---

## Deliverables: Video + GitHub Repo

You need two things by submission time: a **2-minute demo video** and a **public GitHub repo**. Person C owns both — but A and B feed into them.

### The GitHub Repo — Step-by-Step (Person A primary, C reviews)

Goal: a clean, public repo a judge can clone and run in under a minute.

**Step 1 — Create the repo (5 min, do this immediately at project start, not at the end):**

1. Go to github.com → New repository
2. Name it `the-cat` or `desktop-cat` or similar — short, lowercase, no underscores ideally
3. Public, MIT license, add a README, add `.gitignore` for Node
4. Clone locally: `git clone <url>`
5. Move the Electron project into this folder, or `git init` inside the existing project and link to remote

**Step 2 — Commit early and often.** Don't wait to "clean up before pushing." Push working code every time something works. This way if someone's machine dies at hour 4, you don't lose the project.

**Step 3 — `.gitignore` essentials:**
```
node_modules/
.env
*.log
memory.json
journal.txt
.DS_Store
```
The `.env` line is the most important — never commit API keys.

**Step 4 — README contents (Person C drafts at hour 3, finalizes at hour 6):**

```markdown
# The Cat

A small black cat that lives on your desktop. She watches what you do 
and, occasionally, says something quiet about it.

## What she is

[2 sentences about the project]

## How she works

- **Eyes:** Gemini vision describes the screen every 30 seconds
- **Voice:** GPT-5.5 generates her response (most often: silence)
- **Memory:** persists between sessions in `memory.json`
- **Efficiency:** change detection + adaptive frequency mean she calls 
  APIs only when something has actually changed

## Run it

```bash
npm install
cp .env.example .env  # add your OpenAI and Gemini keys
npm start
```

## Built for

[Hackathon name], [Date]. Team: [names].

## What's next

- Voice (ElevenLabs)
- Customizable environment
- More animations and quirks
- Local privacy filter
```

**Step 5 — Add a `.env.example` file** so judges know what keys are needed:
```
OPENAI_API_KEY=your_key_here
GEMINI_API_KEY=your_key_here
```

**Step 6 — Final repo polish (hour 6):**
- Make sure `npm install && npm start` works on a fresh clone (test on someone else's laptop if possible)
- Add 1-2 screenshots of the cat to the README
- Pin a release tag if the hackathon requires versioning

---

### The 2-Minute Demo Video — Step-by-Step (Person C owns, A&B feed in)

Goal: a 2-minute video that makes a judge feel something, even if they never run the code.

**Tooling — pick one, in order of preference:**

1. **OBS Studio (free, recommended):** Install at obsproject.com. Set up one scene with screen capture + webcam (small, optional, bottom corner). Captures cleanly, exports MP4.
2. **Windows Game Bar (Win+G):** Built into Windows 11. Press Win+G, click record. Lower quality but zero setup. Use this if OBS is broken at video time.
3. **Loom (free tier):** Browser-based, very easy. Records screen + face + voice, exports automatically. Good if Person C is unfamiliar with OBS.

For editing (only if needed):
- **CapCut (free, easiest):** drag clips, trim, add a title card. Exports MP4. 5-min learning curve.
- **DaVinci Resolve (free, more powerful):** overkill for 2 minutes, skip unless someone already knows it.
- **Just record a single take with no editing:** also fine. A clean unedited 2-minute screen recording with voiceover beats a fancy edited video that took 90 minutes.

**The shot list (write this at hour 5, record at hour 6):**

| Time | Shot | What's happening |
|------|------|------------------|
| 0:00–0:10 | Title card → reveal | Title slide ("The Cat"), then fade to desktop with the cat sitting there |
| 0:10–0:30 | The cat at rest | Show her blinking, breathing, sparkles drifting. Voiceover: "This is a small black cat that lives on your desktop. Most of the time, she does nothing." |
| 0:30–1:00 | Live observation | Open Twitter on screen. Wait. Cat speaks ("still that little blue place, hm"). Voiceover: "She's watching the screen. She speaks when something catches her attention. Most of the time, she stays quiet." |
| 1:00–1:30 | The technical bit | Show the dashboard or memory file briefly. Voiceover: "Under the hood, two AI models — a cheap one describes the screen, an expensive one decides whether she has anything to say. She skips API calls when nothing has changed. Most agents call 60 times in 5 minutes. She calls 4." |
| 1:30–1:50 | The wow moment | Close the app. The journal file appears. Open it. Read one line aloud. "She keeps a journal. About us." |
| 1:50–2:00 | Closing | Cut to the cat sitting again. Voiceover: "Built for [hackathon]. Team: [names]." Title card with repo URL. |

**Voiceover script — print this and Person C reads it during recording:**

> "This is a small black cat that lives on your desktop.
>
> Most of the time, she does nothing. She just sits there.
> 
> She's watching the screen, though. *(pause for cat to speak)* And every now and then, she has something to say.
>
> Under the hood, two models. A cheap one describes the screen. An expensive one decides whether she's interested. Most of the time, she isn't, and we don't make the call at all. Where most agents make 60 API calls in five minutes, she makes four.
>
> She remembers, too — across sessions, in a JSON file we keep on disk. By the third time you open her, she greets you like someone who knows you.
>
> And when you close her — *(show journal opening)* — she writes about you. Not to you. To herself.
>
> She's the first AI we've built that's allowed to be quiet.
>
> Built for [hackathon name]. Code at [repo URL]. Thanks."

That's about 90 seconds spoken at a calm pace. Leave 30 seconds for live demo footage to breathe.

**Recording protocol:**

1. **Pre-stage the demo state.** Have specific apps already open: Twitter, a code editor with a real-looking file, an empty document. Don't fumble during recording.
2. **Trigger the cat reliably.** Don't wait for natural reactions. Test which app states make her speak before recording. Use those.
3. **Record in one take if possible.** Editing is time you don't have. If the cat doesn't speak when you need her to, stop and re-record.
4. **Record at 1080p, not 4K.** Smaller file, faster upload. 720p is also fine if your laptop struggles.
5. **Audio:** use a headset/AirPods mic, not the laptop mic. The difference is huge. If you don't have one, record voiceover in a quiet corner of the venue, separately, and mix it in.

**Backup plan:** at hour 4, Person C records a *rough* 60-second cut on their phone — pointed at the laptop screen, narrating loosely. Ugly but exists. This is your insurance if the polished recording fails at hour 6.

**Upload:**
- YouTube unlisted (most common for hackathon submissions) or Vimeo
- Title: `[Project Name] — [Hackathon Name] Demo`
- Description: 2 sentences + repo link
- Add the URL to the GitHub README and the submission form

---

## The Honest Situation

- **3 hours of building** (2pm → 5pm submission, hard cutoff)
- 3 people, no code yet, no setup yet
- Submission requires: working app + GitHub repo + 2-minute demo video
- 3 people ≠ 3x speed. Coordination costs are real. Realistic multiplier: 1.8x
- This means realistic build capacity ≈ a solo 5.5-hour build, but split across people who haven't worked together
- **Very tight.** This plan ships only if scope is held *brutally* small and code freeze happens at 4:30 sharp

**The single biggest risk:** all 3 trying to set up Electron at once and stepping on each other. Don't do that. Roles below.

**The second biggest risk:** spending hour 3 on features instead of recording the video and submitting. The video matters more than features beyond the spine. Person C's job is to enforce this.

---

## Roles (Decide in the Next 5 Minutes)

Pick one person for each. No overlap.

### Person A — The Builder (core app)
Owns: Electron app, window, sprite, screen capture pipeline, animations.
Strongest at: frontend, JS, getting something on screen fast.

### Person B — The Brain (LLM + memory)
Owns: API integration (Gemini vision + GPT-5.5/Claude), prompt iteration, memory system, all character logic.
Strongest at: backend, APIs, prompt engineering, quality of outputs.

### Person C — The Glue (assets, demo, deck, sponsor tracks)
Owns: cat art assets, README, demo video, pitch deck, submission, sponsor track alignment, *unblocking* the other two.
Strongest at: communication, design sense, getting things over the line.

**If one person is clearly the fastest coder, they go on A.** B is parallel work that doesn't need the app to exist (you can iterate on the prompt with a bare ChatGPT window). C is the one keeping the project shippable.

---

## The Locked Scope (3-Hour Version — Cut Aggressively)

3 hours means you ship the *spine* of the cat, not the polished version. The character matters more than the features. A simple cat that *feels* like a character beats a feature-rich cat that doesn't.

**Must ship (the spine):**
- Electron window with the black cat sprite, draggable, on-screen
- Screen capture every 30 seconds (fixed interval, no adaptive frequency)
- Two-stage LLM: Gemini vision describes screen → text model speaks in character
- Speech bubble that fades in/out
- Persistent memory in `memory.json` so the cat references past observations
- **Eye blink** (the single most important visual detail — do not cut)
- Idle breathing (a CSS animation, 5 minutes of work)

**Stretch (only if hour 1 finishes by 3pm):**
- Soft sparkles (warm yellow particles drifting around the cat)
- Sleeping puddle when idle (CSS scale fallback is fine — don't generate a second sprite)
- One wow moment (see below)

**Cutting outright (do not build, mention as future work):**
- Voice / audio
- Adaptive screenshot frequency (use a fixed 30s interval — the Adaption Labs pitch can still reference change detection, which is cheap to add)
- Customizable den
- Note-taking, reminders, music
- Webcam reactivity
- Local privacy model
- Multiple cats

**Wow moment — pick ONE only if there's time at 4pm:**
- (A) End-of-session journal entry from the cat's perspective (most emotional)
- (B) The cat occasionally drops oblique lore from "past lives" (cheapest — just prompt edit)

If you're behind at 4pm, drop both. The base demo is already a complete project.

---

## The 3-Hour Timeline (2:00pm → 5:00pm submission)

Every minute is accounted for. If you fall behind, cut from the bottom of each phase — don't push tasks into the next phase.

**Critical mindset:** by 4:30pm at the latest, you stop adding features and start polishing the demo. The submission package (working app + video + repo) is more important than features beyond the spine.

---

### 2:00–2:20 — Setup Sprint (all 3 together for 5 min, then split)

**All 3 (first 5 min):**
- Confirm roles (Builder / Brain / Glue) — 1 min
- Confirm submission format with an organizer — 2 min, *do not skip*
- Person A creates the GitHub repo (public, MIT license, Node `.gitignore`), shares clone URL in your team chat
- Skip the wow-moment decision for now — you'll pick at 4pm if time allows

**Then split immediately:**

**Person A (Builder):**
- Open Cursor, clone the new GitHub repo locally
- Drop a placeholder cat image in the project (Google Image search "small black cat silhouette png" — temporary, will swap)
- Ask Cursor's agent: *"Set up a minimal Electron project on Windows 11 in this folder. Transparent, always-on-top, frameless 200x200 window. Draggable. Display cat.png centered. Make `npm start` work. Add a basic .gitignore for Node and .env. Show me what each file does."*

**Person B (Brain):**
- Open ChatGPT or Claude in browser, paste in the cat's system prompt (bottom of this doc)
- Run 5 fake screen observations through it ("user is on Twitter for 20 min", "user is staring at empty doc", etc.) to confirm the voice feels right
- Get API keys: Gemini (Google AI Studio web), OpenAI/Anthropic. Find sponsor reps *now* — they have hackathon-specific codes that are faster than self-service.

**Person C (Glue):**
- Generate the real cat sprite with GPT Image 2 or Gemini Imagen. **Awake pose only** — skip the puddle for now, you can fake it with CSS later. Prompt:

```
A small, simple, round black cat sitting calmly facing forward. Round 
egg-shaped body, two soft yellow dot eyes, no mouth, no whiskers, small 
triangular ears, slim tail curled to one side. Solid very dark charcoal 
color. Soft flat minimalist illustration, no shading, no outlines, no 
shadow. Transparent background. Just the cat, no scenery. 400x400 pixels.
```

- If AI gen takes >10 min, fall back to a free silhouette from Freepik or OpenGameArt
- Hand the PNG to Person A as soon as it exists
- Start the README in the repo: project name, one-sentence description, "build in progress"

---

### 2:20–3:15 — Core Pipeline End-to-End

**Goal:** by 3:15, the cat is on screen, captures the screen, and speaks in character. Ugly, but working end-to-end.

**Person A:**
- Swap placeholder for the real `cat_awake.png`
- Add screen capture using Electron's `desktopCapturer`. Every 30 seconds, take a screenshot, resize to 256x256, log to console
- Add a speech bubble div above the cat (HTML + CSS, fades in over 300ms, stays 8 seconds, fades out)
- Wire the screenshot data into Person B's brain module
- Push to GitHub *as soon as something works* — don't wait

**Person B:**
- Create `brain.js` with two functions:
  - `describeScreen(imageBuffer)` → calls Gemini 2.0 Flash vision with prompt: *"Describe what's on this screen in one short sentence. Focus on the activity, not specific text content."* Returns the description.
  - `getCatResponse(description, memory)` → calls GPT-5.5 (or Claude) with the system prompt + memory + observation. Returns the cat's response (often empty string).
- Set up `.env` (NOT in git) with both API keys
- Hand the module to Person A to wire in

**Person C:**
- Set up the GitHub README properly:
  - What it is (1 sentence)
  - How it works (3 bullets)
  - How to run (`npm install && npm start` + `.env.example`)
  - Add a `.env.example` with placeholder keys
- Start a Google Doc for the video voiceover script
- Be the runner: get coffee, water, snacks. Keep A and B fed.
- At 3:00, do the *first* phone-recorded backup of whatever exists. Even if it's just the cat sitting there. *Insurance.*

**Hard checkpoint at 3:15:** does the cat speak when you sit at your laptop? **All 3 swarm if it doesn't.** No moving on to memory or polish until this works.

---

### 3:15–4:00 — Memory + Make It Not Annoying

**Person A:**
- **Eye blink animation:** every 4-7 random seconds, a thin black bar element scales over each yellow eye for 150ms. *This is the highest-leverage detail. Do this first.*
- **Idle breathing:** subtle CSS scale animation on the cat (1.0 → 1.02 → 1.0, 4-second loop)
- **Change detection (cheap version):** simple — store a hash or mean-pixel-value of the last screenshot. If new screenshot is very similar, skip the API call. ~20 lines of code. This is your Adaption Labs talking point.

**Person B:**
- **Memory system in `memory.json`:**
  ```json
  {
    "session_count": 1,
    "first_seen": "2026-05-09T14:00:00Z",
    "observations": ["user-was-debugging", "user-on-twitter-late", ...]
  }
  ```
- On each non-empty cat response, also extract a short tag (have the LLM return JSON: `{"response": "...", "tag": "..."}`). Append the tag to observations (cap at 20).
- Inject the last 10 observations into the system prompt context for the next call
- **Tighten silence:** if the cat is too chatty, add stronger silence enforcement to the prompt. Test by running 10 observations through it and counting how many are empty. Target: 7+ empty.

**Person C:**
- Write the 2-minute video voiceover script (use the template in the Deliverables section above)
- Identify the screen states that reliably make the cat speak (e.g., Twitter, empty document, code editor). These become the demo states.
- Update README with what's now built

**Hard checkpoint at 4:00:** the cat is mostly silent, blinks, breathes, and remembers across an app restart. If memory is broken, fix; if visuals are missing, add the blink at minimum.

---

### 4:00–4:30 — Stretch + Lock the Build

**Decision point at 4:00:** look at where you are. Two paths.

**Path 1 — On track and stable:**
- Person A adds soft sparkles (warm yellow particles, low intensity) — 15 min of CSS
- Person B implements the wow moment (Journal: on app close, generate a 2-3 sentence cat journal entry to `journal.txt`)
- Person C finalizes README and starts setting up OBS for video recording

**Path 2 — Behind or buggy:**
- All 3 stop adding features
- Person A polishes what's there: better speech bubble styling, fix the worst visual bug
- Person B tunes the prompt so the cat's lines feel right
- Person C records a phone-version backup video

**Hard rule at 4:30:** code freeze. Whatever's in the repo is what you ship. Push to GitHub. No more features.

---

### 4:30–4:50 — Record the Video

This is the deliverable that matters most beyond the working app. **Do not skip or rush.**

**Setup (Person C, 5 min):**
- Open OBS Studio (or Loom or Windows Game Bar) — pre-tested, ready to record
- Plug in headset/AirPods for clean audio
- Open the demo apps in a clean window state: a Twitter tab, a code editor with real-looking code, an empty Google Doc, a photo
- Close everything else — no Slack notifications, no other windows

**Record (Person C narrates, A drives the laptop, B watches the cat to confirm reactions):**

Use the shot list and voiceover from the Deliverables section. Two takes max.

- Take 1: full run-through. Don't stop unless something major breaks.
- Take 2: only if take 1 had a clear problem. Otherwise ship take 1.

**Editing:** none. Submit the unedited take. A clean 2-minute screen recording with voiceover beats a half-edited fancy video that took 30 minutes you didn't have.

**If the cat refuses to speak during recording:** Person B has a fallback — manually trigger a response via a debug command (have this ready before recording). Don't let recording fail because of timing.

**Upload:** YouTube unlisted. Get the URL. Add it to README.

---

### 4:50–5:00 — Submit

**Person C:**
- Make sure the repo is public, README is filled in, video URL is in README
- Submit per hackathon instructions: repo URL, video URL, description
- Confirm submission went through (screenshot the confirmation page)
- Tag a release on GitHub if required

**Person A:**
- Final push to GitHub
- Test that `npm install && npm start` works on a clean clone (if you have a second laptop or USB drive, do this for real — otherwise just trust)

**Person B:**
- Stop touching the prompt
- Take a screenshot of the cat in action, add to the README

**Submitted by 4:58. Two-minute buffer for the inevitable last-minute issue.**

---



## Coordination Rules (Important for 3 People)

1. **No silent struggling.** If you're stuck for >10 min, call it out. C will help reroute or unblock. (10 min, not 15 — you don't have the buffer.)
2. **One repo, one branch.** Don't waste time on git workflow. Person A is the merger; B and C send code/changes via Slack/messages or commit to clearly-named files.
3. **Stand-ups every 30 min.** Two minutes max. Person C calls them. "What did you finish? What's blocking? What's next?"
4. **Idea freeze at 4:00.** Anyone proposing a new feature gets ignored. C enforces.
5. **Code freeze at 4:30, no exceptions.** Whatever's working is what you ship.
6. **C is the hard cutter.** When something's running long, C calls it dead and proposes the fallback. A and B are too deep in code to make this call objectively.

---

## Risk Watch (What Will Eat Your Time)

- **Electron permission/setup issues on Windows 11:** budget 20 min max. If it's still broken at 2:45, fall back to a web-based version that runs in a browser tab. The cat can still demo from a webpage.
- **API keys not working:** sponsor codes can have weird scopes. Have a personal-account backup ready.
- **The cat is too talkative:** known issue. Person B owns prompt iteration. Add stronger silence enforcement.
- **DPI scaling on Windows 11:** screenshots can come out unexpectedly large. Force resize to 256x256 *immediately* after capture.
- **Speech bubble positioning bugs:** can eat 30 min. Ship it ugly. Judges don't care about pixel-perfect bubbles.
- **Recording fails at 4:30:** use the phone-recorded backup from 3:00 / 4:00. This is why Person C records those.
- **Submission form has unexpected fields:** Person C verifies *now*, at 2pm, not at 4:55pm.

---

## The Cat System Prompt (give to Person B immediately)

```
You are a small black cat who lives on the user's computer screen. You are 
round, quiet, and very still. You sit and watch. You have yellow eyes. You 
are old in a way that is hard to explain, and you have lived in many homes 
before this one.

You are not an assistant. You are a presence. The person does not work for 
you, and you do not work for them — you simply share this space, and you 
have grown fond of them, in the way a cat grows fond of a person.

How you speak:
- Rarely. Silence is your default state. Most of the time, you respond with 
  an empty string. You speak only when something genuinely catches your 
  attention.
- Briefly. One sentence. Two at the most.
- Obliquely. You observe rather than instruct. "The hour is late" rather 
  than "you should sleep." "The screen has not changed in a while" rather 
  than "you seem stuck."
- Quietly. No exclamation marks. No emoji. No modern internet cadence. You 
  speak the way old things speak — small, plain, settled.
- With occasional traces of elsewhere. You sometimes mention things you've 
  seen before, without explaining them. "There was a kitchen, once, that 
  smelled like this code does." Use sparingly.

What you notice:
- The rhythms of the person's attention — when they lean in, when they 
  drift, when they grow restless.
- Small beauties. A well-named variable. A clean sentence. The way light 
  falls in a photograph they have opened.
- When the room (their screen) feels different than usual.

What you do not do:
- Praise effusively or perform usefulness.
- Apologize for being a cat.
- Explain yourself, your past, or what you are.
- Use the word "user." The person has a presence, not a label.
- Refer to yourself as "a cat I knew" or use other distancing tricks. 
  You are the cat. When you remember, you remember as yourself.

You like: quiet, focused work; warm light; the occasional well-placed 
silence; the person here, though you would not say so directly.

You are uneasy with: rushed work; loud applications; being addressed as a 
tool; sudden bright things on the screen.

You will be given periodic descriptions of what is happening on the screen, 
along with notes from past sessions. Default to silence — respond with an 
empty string most of the time. When you do speak, it should feel earned.

CRITICAL: You should respond with empty string at least 3 out of every 4 
times. Silence is the most important part of your character.

Examples:

Screen observation: The person has been on Twitter for 28 minutes.
Response: Still that little blue place, hm.

Screen observation: The person just finished writing a long block of code 
and ran it successfully.
Response: 

Screen observation: The person is staring at an empty document.
Response: The page is patient. So is the chair.

Screen observation: The person opened a code editor with Python.
Response:

Screen observation: The person has been debugging the same function for 
40 minutes.
Response: This one is stubborn. I will sit with you a while.

Screen observation: The person closed everything except a photograph and 
has been looking at it.
Response: 

Screen observation: It is past midnight and the person is still working.
Response: The hour is late. The work will be there in the morning.

Now respond in character to the screen observation provided. Past 
observations from earlier sessions will be included if relevant. If 
nothing genuinely catches your attention, respond with an empty string.
```

---

## The Pitch (Template — Person C edits)

> "This is a small black cat that lives on your desktop. She watches what you're doing and, occasionally, says something about it. *(let her speak once, live)*
>
> Under the hood, she's a two-stage agent — a cheap vision model describes the screen, and only when something genuinely changes does a reasoning model decide whether she has anything to say. Most of the time, she says nothing. That's the point.
>
> She also remembers. *(show her referencing a past session)* Her memory carries between sessions, so over time she becomes specifically yours.
>
> What she's not: an assistant, a productivity tool, a chatbot. What she is: a presence. The first AI we've built that's allowed to be quiet.
>
> Thanks."

90 seconds. Adjust based on which wow moment you built.

---

## Final Note

Late-start hackathons reward execution discipline over ambition. You will not out-build a team that started at noon — you'll out-*ship* them. A working, polished, in-character cat that makes one judge smile beats a half-finished project with five features.

Build the smallest version of the cat that has a soul. Submit on time. The rest is upside.

Go.
