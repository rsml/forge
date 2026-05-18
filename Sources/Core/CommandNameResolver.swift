import Foundation

/// Pure helpers for resolving a human-meaningful name for a running process.
///
/// The daemon owns the I/O (reading `KERN_PROCARGS2`, calling `proc_pidpath`);
/// this module owns the *interpretation* of those signals. Living in Core keeps
/// the logic testable without spawning processes.
public enum CommandNameResolver {

    /// Decide which name to display given the kernel-derived signals.
    ///
    /// Caller provides:
    /// - `argv`: full argument list from `KERN_PROCARGS2` (may be empty if
    ///   the sysctl failed — sandboxing, EPERM on protected processes, etc.)
    /// - `execPath`: resolved binary path from `proc_pidpath` (may be empty)
    ///
    /// Returns the best name we can infer, or nil if every signal is unusable.
    /// Callers (the close-confirmation prompt) substitute `"a process"` for nil.
    ///
    /// Layered fallback (first useful answer wins):
    ///
    /// 1. **argv[0] basename.** This is the path the shell passed to `execve` —
    ///    preserved *before* symlink resolution. For
    ///    `~/.local/bin/claude → ~/.local/share/claude/versions/2.1.141`, argv[0]
    ///    is `…/bin/claude` so basename is `claude` — not `2.1.141`.
    ///
    /// 2. **Interpreter unwrap.** If argv[0]'s basename names a known scripting
    ///    interpreter (`node`, `python3`, `bun`, …) *and* argv[1] exists, use
    ///    argv[1]'s basename with the script extension stripped. Surfaces `cli`
    ///    for `node /usr/local/lib/node_modules/foo/cli.js`.
    ///
    /// 3. **Exec path basename.** Fallback when argv was unavailable (rare,
    ///    e.g. protected processes that block `KERN_PROCARGS2`).
    ///
    /// 4. **Version-name guard.** At every step, names that look like bare
    ///    version numbers (`/^[0-9]+(\.[0-9]+)*$/`) are rejected — they come
    ///    from versioned filenames and never reflect what the user typed.
    public static func resolve(argv: [String], execPath: String) -> String? {
        if let argv0 = argv.first {
            let argv0Name = basename(argv0)
            if isInterpreter(argv0Name), argv.count >= 2 {
                let scriptName = basename(argv[1])
                let stripped = stripScriptExtension(scriptName)
                if isUsefulName(stripped) { return stripped }
            }
            if isUsefulName(argv0Name) { return argv0Name }
        }

        let execName = basename(execPath)
        return isUsefulName(execName) ? execName : nil
    }

    /// True iff the name is non-empty, reasonably short, and not a pure
    /// version-number string.
    public static func isUsefulName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 32 else { return false }
        if isVersionLike(name) { return false }
        return true
    }

    /// True iff `s` is composed entirely of ASCII digits and dots, and
    /// contains at least one digit. Matches `2.1.141`, `42`, `0.0.0`.
    /// Does not match `claude`, `2.1.141-beta`, `.`.
    public static func isVersionLike(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        var sawDigit = false
        for ch in s {
            if !ch.isASCII { return false }
            if ch.isNumber { sawDigit = true; continue }
            if ch == "." { continue }
            return false
        }
        return sawDigit
    }

    private static let interpreters: Set<String> = [
        "node", "python", "python3", "ruby", "bun", "deno",
        "bash", "sh", "zsh", "fish", "dash"
    ]
    public static func isInterpreter(_ name: String) -> Bool {
        interpreters.contains(name)
    }

    private static let scriptExtensions: [String] = [
        ".js", ".mjs", ".cjs", ".ts", ".py", ".rb", ".sh"
    ]
    public static func stripScriptExtension(_ name: String) -> String {
        for ext in scriptExtensions where name.hasSuffix(ext) {
            return String(name.dropLast(ext.count))
        }
        return name
    }

    /// Basename in the POSIX sense: the part after the last `/`. Pure-Swift —
    /// no Foundation cross-platform variability.
    public static func basename(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        if let lastSlash = path.lastIndex(of: "/") {
            return String(path[path.index(after: lastSlash)...])
        }
        return path
    }
}
