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
                let process = Process()
                let pipe = Pipe()
                let errPipe = Pipe()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = fullArgs
                process.standardOutput = pipe
                process.standardError = errPipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if process.terminationStatus != 0 {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? ""
                        ForgeLog.log("[tmux] \(fullArgs.joined(separator: " ")) failed: \(errMsg)")
                    }

                    continuation.resume(returning: output)
                } catch {
                    ForgeLog.log("[tmux] exec error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func run(_ args: String...) async -> String? {
        await run(args)
    }
}
