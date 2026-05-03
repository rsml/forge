import Foundation

/// Runs tmux CLI commands off the main thread
struct TmuxCommandRunner: Sendable {
    let tmuxPath: String

    init() {
        self.tmuxPath = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "tmux"
    }

    func run(_ args: [String]) async -> String? {
        let path = tmuxPath
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
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

                    if process.terminationStatus != 0 {
                        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? ""
                        ForgeLog.log("[tmux] \(args.joined(separator: " ")) failed: \(errMsg)")
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
