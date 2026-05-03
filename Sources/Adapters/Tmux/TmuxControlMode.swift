import Foundation

/// Manages a tmux control mode (-CC) connection for push-based state updates
final class TmuxControlMode: @unchecked Sendable {
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = ""
    private let tmuxPath: String
    private var onEvent: (@Sendable (String) -> Void)?

    init(tmuxPath: String) {
        self.tmuxPath = tmuxPath
    }

    func start(onEvent: @escaping @Sendable (String) -> Void) {
        self.onEvent = onEvent

        let process = Process()
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: tmuxPath)
        process.arguments = ["-C", "attach"]
        process.standardOutput = stdoutPipe
        process.standardInput = stdinPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            ForgeLog.log("[control] Started control mode")
        } catch {
            ForgeLog.log("[control] Failed to start: \(error)")
            return
        }

        self.process = process
        self.stdin = stdinPipe.fileHandleForWriting

        let handle = stdoutPipe.fileHandleForReading
        Thread.detachNewThread { [weak self] in
            while let self, self.process != nil {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    self.handleOutput(text)
                }
            }
            ForgeLog.log("[control] Reader thread exited")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdin = nil
    }

    func send(_ command: String) {
        guard let stdin else {
            ForgeLog.log("[control] No stdin for command: \(command)")
            return
        }
        if let data = (command + "\n").data(using: .utf8) {
            stdin.write(data)
        }
    }

    private func handleOutput(_ text: String) {
        buffer += text
        while let idx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<idx])
            buffer = String(buffer[buffer.index(after: idx)...])
            if line.hasPrefix("%") {
                let event = line.split(separator: " ", maxSplits: 1).first.map(String.init) ?? line
                onEvent?(event)
            }
        }
    }
}
