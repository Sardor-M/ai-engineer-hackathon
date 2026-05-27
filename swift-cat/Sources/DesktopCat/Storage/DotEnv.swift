import Foundation

/// Reads `KEY=VALUE` pairs from a `.env` file into the process environment.
///
/// Why this exists: the cat is usually launched via `open build/...app`, which
/// runs in a clean environment — `OPENAI_API_KEY` and friends set in the
/// developer's shell aren't inherited. Without this loader, `open`-launched
/// runs silently lose API keys and every provider falls through to "no key".
///
/// Lookup order (first existing file wins):
///   1. `~/Library/Application Support/DesktopCat/.env` — canonical location
///      that works regardless of the current working directory at launch.
///   2. `$PWD/.env` — fallback for `swift run` from the repo root.
///
/// Already-set environment variables are NEVER overwritten. Explicit
/// `OPENAI_API_KEY=… open build/...app` still wins over the file, so an
/// engineer can override a key for one run without editing the file.
///
/// Format:
///   - `KEY=value` — bare value, no quoting needed
///   - `KEY="value with spaces"` — surrounding double or single quotes stripped
///   - `export KEY=value` — `export` prefix tolerated (POSIX sh style)
///   - `# comment` lines and blank lines ignored
enum DotEnv {
    /// Default lookup paths. Exposed so tests can override.
    static var candidatePaths: [String] {
        [
            AppSupport.file(".env").path,
            FileManager.default.currentDirectoryPath + "/.env",
        ]
    }

    /// Load from the first existing `.env` in `candidatePaths`. Idempotent —
    /// calling twice won't re-apply since already-set vars are skipped.
    static func load() {
        for path in candidatePaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
                Log.env.warn("found \(path) but couldn't read it")
                continue
            }
            let applied = applyContents(contents)
            Log.env.info("loaded \(applied) variable(s) from \(path)")
            return
        }
        Log.env.info("no .env in default locations; using inherited environment only")
    }

    /// Parse `contents` and `setenv` each key whose value isn't already set.
    /// Returns the number of variables applied.
    @discardableResult
    static func applyContents(_ contents: String) -> Int {
        var applied = 0
        for rawLine in contents.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // `export KEY=value` is valid POSIX shell — strip the prefix.
            let stripped = line.hasPrefix("export ")
                ? String(line.dropFirst("export ".count))
                : line

            guard let eq = stripped.firstIndex(of: "=") else { continue }
            let key = String(stripped[..<eq]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            var value = String(stripped[stripped.index(after: eq)...])
                .trimmingCharacters(in: .whitespaces)

            // Strip a matching pair of surrounding quotes.
            if value.count >= 2 {
                let first = value.first
                let last = value.last
                if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                    value = String(value.dropFirst().dropLast())
                }
            }

            // Don't clobber what the launcher already set.
            if ProcessInfo.processInfo.environment[key] != nil { continue }
            setenv(key, value, 1)
            applied += 1
        }
        return applied
    }
}
