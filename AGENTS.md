# Development Rules

Working rules for human + AI collaborators on this repo. The repo is a hybrid:
the Electron cat at the root stays shippable while the Swift rewrite grows in
`swift-cat/`. See [`docs/SWIFT_REWRITE.md`](docs/SWIFT_REWRITE.md) for the plan.

## Conversational Style

- Keep answers short and concise.
- No emojis in commits, issues, PR comments, or code.
- No fluff or cheerful filler text.
- Technical prose only, kind but direct (e.g., "Thanks @user" not "Thanks so much @user!").

## Code Quality

### Swift (`swift-cat/`)

- Target macOS 13+, Swift 5.9+. Do not lower the deployment target without a stated reason.
- Prefer `struct` over `class`; reach for `class` only when reference identity or `AnyObject` constraints actually require it.
- Annotate concurrency boundaries deliberately: `@MainActor` for AppKit / view code, `Sendable` for types that cross actor hops. Don't sprinkle `@MainActor` to silence warnings — fix the underlying ownership.
- No force unwraps (`!`) and no `try!` in product code. Test fixtures may use `XCTUnwrap`.
- No `Any` / `AnyObject` in public APIs unless the platform demands it (e.g., `NSEvent` callbacks).
- Use `URLSession` directly for HTTP. Don't pull in `Alamofire` etc. for a few requests.
- Resources (PNGs, JSON) go under `Sources/DesktopCat/Resources/` and are loaded via `Bundle.module`. Don't hard-code absolute paths.
- Persist user state under `~/Library/Application Support/DesktopCat/` via `AppSupport.swift` helpers, never `UserDefaults` for anything non-trivial.
- Network keys live in env vars (`OPENAI_API_KEY`, `GEMINI_API_KEY`, `ELEVENLABS_API_KEY`) — never commit them and never read them from disk.

### Electron (`/` root, legacy)

- The Electron app is in maintenance mode until Phase 4 cutover. Bug fixes only; do not add features.
- Keep `brain.js` / `renderer.js` / `main.js` in sync with `swift-cat/` semantics when porting (prompts, rate limits, voice profile mapping).
- No new `.js` dependencies without a stated reason — bundle size matters for the DMG.

### General

- No backwards-compatibility shims unless the user explicitly asks for them.
- Always ask before removing functionality that appears intentional.
- Do not preserve dead code with `// removed` comments. Delete it.

## Commands

After Swift code changes:

```bash
cd swift-cat
swift build               # must compile clean (warnings count as errors for review)
make release              # release build — keeps binary < 5 MB target
```

After Electron code changes (root): there is no `npm run check` here. Run the app
locally and exercise the touched path.

- `npm start` — launches the Electron app for manual verification.
- `npm test` — not configured; do not invent test commands.
- Never run `npm install <something>` without asking.

### Hand-off rules

The user prefers to run app launches (`swift run`, `npm start`, `make
open-bundle`) themselves so they can see the cat / observe behavior. Don't
spawn those processes from Bash — describe what to run and wait for the user
to report what they saw. Read-only checks (`swift build`, `git status`, file
reads) are fine.

## Commits

- Conventional-commit prefix: `feat(swift):`, `fix(swift):`, `feat(electron):`, `chore:`, `docs:`, `refactor:`.
- One commit per logical change. Don't squash unrelated work.
- Reference issues with `fixes #N` / `closes #N` when applicable.
- Never `git add -A` or `git add .`. List specific paths so unrelated files don't sneak in.

NEVER commit unless the user asks.

## Pull Request Workflow

This repo is the personal fork `Sardor-M/ai-engineer-hackathon`. PRs target
`main` on the same fork. The original `am3lia-low/ai-engineer-hackathon` is
upstream but the user no longer PRs there — treat fork main as the source of
truth.

Workflow:

1. Branch from `main` with a `feat/…`, `fix/…`, or `chore/…` prefix.
2. Push to `origin` (= fork) over HTTPS so the `gh` token is used. SSH push will fail because the local SSH key resolves to a different GitHub account.
3. `gh pr create` — no `--repo` flag needed; defaults to origin.
4. CI runs two workflows:
   - **`Claude PR Review`** — line-level review with cost guard (skips diffs > 4000 lines).
   - **`Claude Code`** — `@claude` mention bot for follow-ups in comments.
5. Merge into `main` after review settles. Delete the branch.

PRs are kept small: ~500 lines of diff each. Split bigger work across multiple PRs (e.g., the migration is split phase-by-phase).

## When Posting Issue / PR Comments

- Write the full comment to a temp file and use `gh issue comment --body-file` / `gh pr comment --body-file`. Don't pass multi-line markdown via `--body`.
- Preview the exact text before posting.
- Post exactly one final comment unless the user asks for multiple.
- If a comment is malformed, delete it and post a single corrected one.
- Keep comments concise and technical.

## Forbidden Git Operations

These can destroy work — never run without explicit user authorization:

- `git reset --hard`
- `git checkout .` / `git restore .`
- `git clean -fd`
- `git stash` (stashes everything, including any parallel work)
- `git add -A` / `git add .`
- `git push --force` (especially to `main`)
- `git commit --no-verify` (do not bypass hooks)

If a rebase conflicts in a file you didn't touch, abort and ask.

## Documentation

- `docs/SWIFT_REWRITE.md` is the high-level 4-phase outline — keep it short.
- Deep drafts, trackers, dated logs, and personal planning notes go in
  `docs/migration/`, which is gitignored. Never commit anything from there.
- `README.md` (root, Electron) and `swift-cat/README.md` stay user-facing.
  Don't dump implementation detail into them.

## Secrets / Privacy

- `.env` is gitignored — never commit it.
- The `ELEVENLABS_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `WHISPER_API_KEY` env vars are all the cat needs. Don't add config files that duplicate them.
- The cat captures screen content and Mail bodies. Never log full captures or full mail bodies to stdout — log lengths / fingerprints only.

## User Override

If user instructions conflict with anything written here, ask once for
confirmation that they want to override the rule. Only then execute.
