import Foundation

/// Manages a tmux control mode (-CC) connection for push-based state updates.
/// Automatically reconnects when the connection drops (e.g., after switch-client).
final class TmuxControlMode: @unchecked Sendable {
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = ""
    private let tmuxPath: String
    private let socketName: String
    private let configPath: String?
    private var onEvent: (@Sendable (String) -> Void)?
    private var shouldReconnect = false
    private var consecutiveFailures = 0
    private let maxRetries = 5
    private let lock = NSLock()

    init(tmuxPath: String, socketName: String = "forge", configPath: String? = nil) {
        self.tmuxPath = tmuxPath
        self.socketName = socketName
        self.configPath = configPath
    }

    func start(onEvent: @escaping @Sendable (String) -> Void) {
        lock.lock()
        self.onEvent = onEvent
        self.shouldReconnect = true
        self.consecutiveFailures = 0
        lock.unlock()
        launchProcess()
    }

    func stop() {
        lock.lock()
        shouldReconnect = false
        let proc = process
        process = nil
        stdin = nil
        lock.unlock()
        proc?.terminate()
    }

    func send(_ command: String) {
        lock.lock()
        // Reconnect immediately if the connection is dead
        if process == nil || !(process?.isRunning ?? false) {
            lock.unlock()
            launchProcess()
            lock.lock()
        }
        guard let stdin else {
            lock.unlock()
            ForgeLog.log("[control] No stdin for command: \(command)")
            return
        }
        lock.unlock()
        if let data = (command + "\n").data(using: .utf8) {
            stdin.write(data)
        }
    }

    private func launchProcess() {
        lock.lock()
        // Don't launch if already running
        if let existing = process, existing.isRunning {
            lock.unlock()
            return
        }
        lock.unlock()

        let proc = Process()
        let stdoutPipe = Pipe()
        let stdinPipe = Pipe()
        let stderrPipe = Pipe()

        var args = ["-C", "-L", socketName]
        if let configPath {
            args += ["-f", configPath]
        }
        args += ["attach"]

        proc.executableURL = URL(fileURLWithPath: tmuxPath)
        proc.arguments = args
        proc.standardOutput = stdoutPipe
        proc.standardInput = stdinPipe
        proc.standardError = stderrPipe

        do {
            try proc.run()
            ForgeLog.log("[control] Started control mode")
        } catch {
            ForgeLog.log("[control] Failed to start: \(error)")
            return
        }

        lock.lock()
        self.process = proc
        self.stdin = stdinPipe.fileHandleForWriting
        self.buffer = ""
        lock.unlock()

        // Read stderr on a separate thread for diagnostics
        let errHandle = stderrPipe.fileHandleForReading
        Thread.detachNewThread {
            let data = errHandle.readDataToEndOfFile()
            if let msg = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !msg.isEmpty {
                ForgeLog.log("[control] stderr: \(msg)")
            }
        }

        let handle = stdoutPipe.fileHandleForReading
        Thread.detachNewThread { [weak self] in
            var receivedData = false
            while let self {
                self.lock.lock()
                let isCurrentProcess = self.process === proc
                self.lock.unlock()
                guard isCurrentProcess else { break }

                let data = handle.availableData
                if data.isEmpty { break }
                receivedData = true
                if let text = String(data: data, encoding: .utf8) {
                    self.handleOutput(text)
                }
            }
            ForgeLog.log("[control] Reader thread exited")
            self?.handleDisconnect(wasConnected: receivedData)
        }
    }

    private func handleDisconnect(wasConnected: Bool) {
        lock.lock()
        process = nil
        stdin = nil

        if wasConnected {
            // Successful connection that later dropped — reset failure counter
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
        }

        let failures = consecutiveFailures
        let shouldReconnect = self.shouldReconnect && failures < maxRetries
        lock.unlock()

        guard shouldReconnect else {
            if failures >= maxRetries {
                ForgeLog.log("[control] Giving up after \(failures) failed attempts. Is the tmux server running?")
            }
            return
        }

        // Exponential backoff: 0.5s, 1s, 2s, 4s, ...
        let delay = min(0.5 * pow(2.0, Double(failures - 1)), 10.0)
        ForgeLog.log("[control] Reconnecting in \(String(format: "%.1f", delay))s (attempt \(failures + 1)/\(maxRetries))...")
        Thread.sleep(forTimeInterval: delay)

        lock.lock()
        let stillShouldReconnect = self.shouldReconnect
        lock.unlock()
        guard stillShouldReconnect else { return }
        launchProcess()
    }

    private func handleOutput(_ text: String) {
        buffer += text
        while let idx = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<idx])
            buffer = String(buffer[buffer.index(after: idx)...])
            if line.hasPrefix("%") && !line.hasPrefix("%output") {
                onEvent?(line)
            }
        }
    }
}
