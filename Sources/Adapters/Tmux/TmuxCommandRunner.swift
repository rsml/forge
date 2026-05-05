import Foundation

/// Runs tmux CLI commands off the main thread
struct TmuxCommandRunner: Sendable {
    let tmuxPath: String
    let socketName: String = "forge"
    let configPath: String?

    init() {
        // 1. Bundled: next to the executable
        let execURL = Bundle.main.executableURL?.deletingLastPathComponent()
        let bundledPath = execURL?.appendingPathComponent("tmux").path
        if let bundledPath, FileManager.default.fileExists(atPath: bundledPath) {
            self.tmuxPath = bundledPath
        } else {
            // 2. System installations (fallback)
            self.tmuxPath = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
                .first { FileManager.default.fileExists(atPath: $0) } ?? "tmux"
        }
        ForgeLog.log("[tmux] Using: \(self.tmuxPath)")

        // Config: user override first, then bundled
        let userConfigPath = (NSHomeDirectory() as NSString).appendingPathComponent(".config/forge/forge-tmux.conf")
        if FileManager.default.fileExists(atPath: userConfigPath) {
            self.configPath = userConfigPath
        } else if let configCandidate = execURL?.appendingPathComponent("forge-tmux.conf").path,
                  FileManager.default.fileExists(atPath: configCandidate) {
            self.configPath = configCandidate
        } else {
            self.configPath = nil
        }
    }

    /// Builds the base arguments that should precede every tmux command
    private var baseArgs: [String] {
        var args = ["-L", socketName]
        if let configPath {
            args += ["-f", configPath]
        }
        return args
    }

    func run(_ args: [String]) async -> String? {
        let fullArgs = baseArgs + args
        let path = tmuxPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let result = Self.execute(path: path, args: fullArgs)

                // Exit 137 = SIGKILL, typically macOS code signing cache rejection
                if result.status == 137 {
                    ForgeLog.log("[tmux] SIGKILL detected (exit 137), re-signing binary...")
                    Self.resignBinary(at: path)
                    let retry = Self.execute(path: path, args: fullArgs)
                    if retry.status != 0 {
                        ForgeLog.log("[tmux] \(fullArgs.joined(separator: " ")) failed after re-sign (exit \(retry.status)): \(retry.error)")
                    }
                    continuation.resume(returning: retry.output)
                    return
                }

                if result.status != 0 {
                    ForgeLog.log("[tmux] \(fullArgs.joined(separator: " ")) failed (exit \(result.status)): \(result.error)")
                }
                continuation.resume(returning: result.output)
            }
        }
    }

    private static func execute(path: String, args: [String]) -> (output: String?, status: Int32, error: String) {
        let process = Process()
        let pipe = Pipe()
        let errPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? ""
            return (output, process.terminationStatus, errMsg)
        } catch {
            ForgeLog.log("[tmux] exec error: \(error)")
            return (nil, -1, error.localizedDescription)
        }
    }

    private static func resignBinary(at path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        ForgeLog.log("[tmux] Re-signed binary at \(path)")
    }

    func run(_ args: String...) async -> String? {
        await run(args)
    }
}
