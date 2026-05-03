import Foundation
import Observation

/// Manages the connection to the tmux server via control mode.
/// Parses the control mode protocol and keeps TmuxState in sync.
@Observable
@MainActor
final class TmuxController {
    var state = TmuxState()

    private var controlProcess: Process?
    private var stdin: FileHandle?
    private var buffer = ""
    private var refreshTask: Task<Void, Never>?

    /// Path to tmux binary
    private let tmuxPath: String = {
        for path in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"] {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "tmux"
    }()

    // MARK: - Connection

    func connect() {
        Task {
            print("[Forge] Connecting to tmux server...")
            print("[Forge] Using tmux at: \(tmuxPath)")

            await ensureServer()
            await refreshState()

            print("[Forge] Found \(state.sessions.count) sessions")
            for s in state.sessions {
                print("[Forge]   - \(s.name) (id=\(s.id), windows=\(s.windowCount))")
            }

            startControlMode()
            startPeriodicRefresh()
            state.connected = true
            print("[Forge] Connected.")
        }
    }

    func disconnect() {
        refreshTask?.cancel()
        controlProcess?.terminate()
        controlProcess = nil
        stdin = nil
    }

    // MARK: - tmux Commands (runs off main thread)

    func run(_ args: String...) async -> String? {
        await run(args)
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
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let errOutput = String(data: errData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 && !errOutput.isEmpty {
                        print("[Forge] tmux \(args.joined(separator: " ")) failed: \(errOutput.trimmingCharacters(in: .whitespacesAndNewlines))")
                    }

                    continuation.resume(returning: output)
                } catch {
                    print("[Forge] tmux exec error: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - State Loading

    private func ensureServer() async {
        let result = await run("list-sessions", "-F", "#{session_id}")
        if result == nil || result?.isEmpty == true {
            print("[Forge] No tmux server running, creating default session...")
            _ = await run("new-session", "-d", "-s", "forge-default")
        }
    }

    func refreshState() async {
        await loadSessions()
        for session in state.sessions {
            await loadWindows(for: session)
            for window in session.windows {
                await loadPanes(for: window)
            }
        }
    }

    private func loadSessions() async {
        let format = "#{session_id}\t#{session_name}\t#{session_windows}\t#{session_attached}\t#{session_path}"
        guard let output = await run("list-sessions", "-F", format),
              !output.isEmpty else {
            print("[Forge] No sessions returned from list-sessions")
            return
        }

        let infos = output.split(separator: "\n").compactMap { line -> TmuxSessionInfo? in
            let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else {
                print("[Forge] Skipping malformed session line: \(line)")
                return nil
            }
            return TmuxSessionInfo(
                id: parts[0],
                name: parts[1],
                windowCount: Int(parts[2]) ?? 0,
                attached: parts[3] != "0",
                path: parts[4].isEmpty ? nil : parts[4]
            )
        }

        state.updateFromList(sessions: infos)

        if state.activeSessionId == nil, let first = state.sessions.first {
            state.activeSessionId = first.id
        }
    }

    private func loadWindows(for session: TmuxSession) async {
        let format = "#{window_id}\t#{session_id}\t#{window_index}\t#{window_name}\t#{window_active}\t#{window_panes}"
        guard let output = await run("list-windows", "-t", session.name, "-F", format),
              !output.isEmpty else { return }

        let infos = output.split(separator: "\n").compactMap { line -> TmuxWindowInfo? in
            let parts = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 6 else { return nil }
            return TmuxWindowInfo(
                id: parts[0],
                sessionId: parts[1],
                index: Int(parts[2]) ?? 0,
                name: parts[3],
                active: parts[4] != "0",
                paneCount: Int(parts[5]) ?? 0
            )
        }

        var updated: [TmuxWindow] = []
        for info in infos {
            if let existing = session.windows.first(where: { $0.id == info.id }) {
                existing.update(from: info)
                updated.append(existing)
            } else {
                updated.append(TmuxWindow(from: info))
            }
        }
        session.windows = updated

        if let active = infos.first(where: { $0.active }) {
            state.activeWindowId = active.id
        }
    }

    private func loadPanes(for window: TmuxWindow) async {
        let format = "#{pane_id}\t#{window_id}\t#{pane_index}\t#{pane_active}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_width}\t#{pane_height}\t#{pane_pid}"
        guard let output = await run("list-panes", "-t", window.id, "-F", format),
              !output.isEmpty else { return }

        let infos = output.split(separator: "\n").compactMap { line -> TmuxPaneInfo? in
            let parts = line.split(separator: "\t", maxSplits: 8, omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 9 else { return nil }
            return TmuxPaneInfo(
                id: parts[0],
                windowId: parts[1],
                index: Int(parts[2]) ?? 0,
                active: parts[3] != "0",
                currentCommand: parts[4],
                currentPath: parts[5],
                width: Int(parts[6]) ?? 80,
                height: Int(parts[7]) ?? 24,
                pid: Int(parts[8]) ?? 0
            )
        }

        var updated: [TmuxPane] = []
        for info in infos {
            if let existing = window.panes.first(where: { $0.id == info.id }) {
                existing.update(from: info)
                updated.append(existing)
            } else {
                updated.append(TmuxPane(from: info))
            }
        }
        window.panes = updated

        if let active = infos.first(where: { $0.active }) {
            state.activePaneId = active.id
        }
    }

    // MARK: - Control Mode

    private func startControlMode() {
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
            print("[Forge] Control mode started.")
        } catch {
            print("[Forge] Failed to start control mode: \(error)")
            return
        }

        controlProcess = process
        stdin = stdinPipe.fileHandleForWriting

        let handle = stdoutPipe.fileHandleForReading
        Task.detached { [weak self] in
            while let self {
                let data = handle.availableData
                if data.isEmpty { break }
                if let text = String(data: data, encoding: .utf8) {
                    await self.handleControlOutput(text)
                }
            }
            print("[Forge] Control mode reader exited.")
        }
    }

    private func handleControlOutput(_ text: String) {
        buffer += text
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
            if line.hasPrefix("%") {
                parseControlLine(line)
            }
        }
    }

    private func parseControlLine(_ line: String) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        guard let notification = parts.first else { return }

        print("[Forge] Control: \(notification)")

        switch notification {
        case "%sessions-changed",
             "%session-changed",
             "%client-session-changed",
             "%session-renamed",
             "%window-add",
             "%window-close",
             "%window-renamed",
             "%window-pane-changed",
             "%layout-change",
             "%pane-mode-changed":
            Task { await refreshState() }

        default:
            break
        }
    }

    func sendCommand(_ command: String) {
        guard let stdin else {
            print("[Forge] Cannot send command, no stdin: \(command)")
            return
        }
        let data = (command + "\n").data(using: .utf8)!
        stdin.write(data)
    }

    // MARK: - Periodic Refresh

    private func startPeriodicRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await refreshState()
            }
        }
    }

    // MARK: - Actions (UI -> tmux)

    func selectSession(_ session: TmuxSession) {
        state.activeSessionId = session.id
        if let window = session.windows.first(where: { $0.active }) ?? session.windows.first {
            state.activeWindowId = window.id
        }
        sendCommand("switch-client -t \(session.name)")
    }

    func selectWindow(_ window: TmuxWindow) {
        state.activeWindowId = window.id
        sendCommand("select-window -t \(window.id)")
    }

    func selectPane(_ pane: TmuxPane) {
        state.activePaneId = pane.id
        sendCommand("select-pane -t \(pane.id)")
    }

    func renameSession(_ session: TmuxSession, to name: String) {
        sendCommand("rename-session -t \(session.name) \(name)")
    }

    func renameWindow(_ window: TmuxWindow, to name: String) {
        sendCommand("rename-window -t \(window.id) \(name)")
    }

    func newSession(name: String, path: String) async {
        print("[Forge] Creating session '\(name)' at \(path)")
        let result = await run("new-session", "-d", "-s", name, "-c", path)
        print("[Forge] new-session result: \(result ?? "nil")")
        await refreshState()
        // Select the new session
        if let session = state.sessions.first(where: { $0.name == name }) {
            selectSession(session)
        }
    }

    func newWindow(in session: TmuxSession, path: String? = nil) {
        var cmd = "new-window -t \(session.name)"
        if let path {
            cmd += " -c \(path)"
        }
        sendCommand(cmd)
    }

    func killSession(_ session: TmuxSession) {
        sendCommand("kill-session -t \(session.name)")
    }

    func killWindow(_ window: TmuxWindow) {
        sendCommand("kill-window -t \(window.id)")
    }

    func clearBell(for pane: TmuxPane) {
        pane.hasBell = false
        pane.status = PaneStatus.from(command: pane.currentCommand)
    }
}
