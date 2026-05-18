import Testing
@testable import ForgeCore

@Suite("CommandNameResolver")
struct CommandNameResolverTests {

    // MARK: - The motivating case

    @Test("claude with versioned-symlink install resolves to 'claude'")
    func claudeVersionedSymlink() {
        // argv[0] is what the shell passed to execve (the launcher path);
        // execPath is what proc_pidpath returns (the resolved symlink target).
        let result = CommandNameResolver.resolve(
            argv: ["/Users/ross/.local/bin/claude", "--session-id", "abc"],
            execPath: "/Users/ross/.local/share/claude/versions/2.1.141"
        )
        #expect(result == "claude")
    }

    // MARK: - argv[0] basename (the primary signal)

    @Test("plain binary in PATH yields its name")
    func plainBinary() {
        let result = CommandNameResolver.resolve(
            argv: ["/usr/bin/vim", "file.txt"], execPath: "/usr/bin/vim"
        )
        #expect(result == "vim")
    }

    @Test("argv[0] without a path component is used directly")
    func bareName() {
        let result = CommandNameResolver.resolve(
            argv: ["top"], execPath: "/usr/bin/top"
        )
        #expect(result == "top")
    }

    // MARK: - Interpreter unwrapping

    @Test("node + script reveals the script name")
    func nodeInterpreter() {
        let result = CommandNameResolver.resolve(
            argv: ["/usr/local/bin/node", "/usr/local/lib/node_modules/foo/cli.js"],
            execPath: "/usr/local/bin/node"
        )
        #expect(result == "cli")
    }

    @Test("python3 + script strips .py")
    func python3Interpreter() {
        let result = CommandNameResolver.resolve(
            argv: ["/usr/bin/python3", "/usr/local/bin/manage.py", "runserver"],
            execPath: "/usr/bin/python3"
        )
        #expect(result == "manage")
    }

    @Test("bun + .ts script strips extension")
    func bunInterpreter() {
        let result = CommandNameResolver.resolve(
            argv: ["bun", "/repo/scripts/build.ts"], execPath: "/usr/local/bin/bun"
        )
        #expect(result == "build")
    }

    @Test("interpreter without argv[1] falls through to argv[0]")
    func interpreterMissingScript() {
        // `node` started with no args (e.g. REPL) — show "node" rather than crash.
        let result = CommandNameResolver.resolve(
            argv: ["/usr/local/bin/node"], execPath: "/usr/local/bin/node"
        )
        #expect(result == "node")
    }

    // MARK: - Version-pattern guard

    @Test("pure version string in argv[0] basename is rejected")
    func versionInArgv0() {
        // Hypothetical: someone exec'd the versioned target directly.
        let result = CommandNameResolver.resolve(
            argv: ["/Users/ross/.local/share/claude/versions/2.1.141"],
            execPath: "/Users/ross/.local/share/claude/versions/2.1.141"
        )
        #expect(result == nil)  // both signals are version-like → caller substitutes "a process"
    }

    @Test("version strings match the guard")
    func versionLikeRecognition() {
        #expect(CommandNameResolver.isVersionLike("2.1.141"))
        #expect(CommandNameResolver.isVersionLike("42"))
        #expect(CommandNameResolver.isVersionLike("0.0.0"))
        #expect(!CommandNameResolver.isVersionLike("claude"))
        #expect(!CommandNameResolver.isVersionLike("2.1.141-beta"))
        #expect(!CommandNameResolver.isVersionLike("v2"))
        #expect(!CommandNameResolver.isVersionLike("."))      // no digit
        #expect(!CommandNameResolver.isVersionLike(""))
    }

    // MARK: - Fallback to execPath

    @Test("argv empty → fall back to execPath basename")
    func emptyArgv() {
        let result = CommandNameResolver.resolve(
            argv: [], execPath: "/usr/bin/htop"
        )
        #expect(result == "htop")
    }

    @Test("argv empty AND execPath empty → nil")
    func nothingUsable() {
        let result = CommandNameResolver.resolve(argv: [], execPath: "")
        #expect(result == nil)
    }

    @Test("argv has only a version-like entry → fall back to execPath")
    func argvVersionFallback() {
        let result = CommandNameResolver.resolve(
            argv: ["2.1.141"], execPath: "/usr/bin/vim"
        )
        #expect(result == "vim")
    }

    // MARK: - Useful-name predicate

    @Test("isUsefulName rejects empty, too-long, and version strings")
    func usefulNameGuards() {
        #expect(CommandNameResolver.isUsefulName("claude"))
        #expect(CommandNameResolver.isUsefulName("a"))
        #expect(!CommandNameResolver.isUsefulName(""))
        #expect(!CommandNameResolver.isUsefulName(String(repeating: "x", count: 33)))
        #expect(!CommandNameResolver.isUsefulName("2.1.141"))
    }

    // MARK: - Basename behaviour

    @Test("basename strips everything up to and including last slash")
    func basenameSemantics() {
        #expect(CommandNameResolver.basename("/usr/bin/vim") == "vim")
        #expect(CommandNameResolver.basename("vim") == "vim")
        #expect(CommandNameResolver.basename("/usr/bin/") == "")
        #expect(CommandNameResolver.basename("") == "")
    }

    // MARK: - Script extension stripping

    @Test("stripScriptExtension removes one known extension")
    func extensionStripping() {
        #expect(CommandNameResolver.stripScriptExtension("cli.js") == "cli")
        #expect(CommandNameResolver.stripScriptExtension("script.py") == "script")
        #expect(CommandNameResolver.stripScriptExtension("worker.mjs") == "worker")
        #expect(CommandNameResolver.stripScriptExtension("README.md") == "README.md") // not in list
        #expect(CommandNameResolver.stripScriptExtension("plain") == "plain")
    }
}
