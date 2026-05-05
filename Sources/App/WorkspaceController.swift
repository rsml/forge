import AppKit
import Foundation
import Observation
import ForgeDomain

/// Orchestrates domain state and tmux adapter.
/// Single @Observable object that all views consume.
@Observable
@MainActor
final class WorkspaceController {
    let workspace = Workspace()
    private(set) var gitBranch: String?
    private let tmux: any TmuxPort
    private var refreshTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var isRefreshing = false
    private var needsRefreshAfterCurrent = false
    private var lastGitBranchSessionId: String?
    private var perSessionActiveWindowId: [String: String] = [:]  // sessionId -> windowId

    init(tmux: any TmuxPort) {
        self.tmux = tmux
    }

    func connect() {
        Task {
            ForgeLog.log("[app] Connecting...")
            await ensureServer()
            await refresh()
            seedRecentDirectories()
            restoreUIState()

            tmux.startControlMode { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(event)
                }
            }

            startPeriodicRefresh()
            workspace.connected = true
            ForgeLog.log("[app] Connected. \(workspace.sessions.count) sessions found.")
        }
    }

    func disconnect() {
        refreshTask?.cancel()
        tmux.stopControlMode()
    }

    // MARK: - State Refresh

    func refresh() async {
        let sessionInfos = await tmux.listSessions()
        let allWindows = await tmux.listAllWindows()
        let allPanes = await tmux.listAllPanes()

        mergeSessionState(sessionInfos)
        let windowsBySession = Dictionary(grouping: allWindows, by: \.sessionId)
        let panesByWindow = Dictionary(grouping: allPanes, by: \.windowId)

        for session in workspace.sessions {
            mergeWindowState(session: session, windowsBySession[session.id] ?? [])
            for window in session.windows {
                mergePaneState(window: window, panesByWindow[window.id] ?? [])
            }
        }

        let activeSessionId = workspace.activeSessionId
        if activeSessionId != lastGitBranchSessionId {
            lastGitBranchSessionId = activeSessionId
            await fetchGitBranch()
        }
        NotificationCenter.default.post(name: .forgeWindowTitleChanged, object: nil)
    }

    // MARK: - Actions

    func selectSession(_ session: Session) {
        // Save current window for the session we're leaving
        if let currentSessionId = workspace.activeSessionId {
            perSessionActiveWindowId[currentSessionId] = workspace.activeWindowId
        }

        workspace.activeSessionId = session.id

        // Restore saved window for the session we're entering
        if let savedWindowId = perSessionActiveWindowId[session.id],
           session.windows.contains(where: { $0.id == savedWindowId }) {
            workspace.activeWindowId = savedWindowId
            Task { await tmux.selectWindow(id: savedWindowId) }
        } else if let window = session.windows.first(where: { $0.active }) ?? session.windows.first {
            workspace.activeWindowId = window.id
        }

        Task { await tmux.switchClient(session: session.name) }
        saveUIState()
    }

    func selectWindow(_ window: Window) {
        workspace.activeWindowId = window.id
        // Clear bell state for all panes in this window
        for pane in window.panes {
            pane.hasBell = false
        }
        Task { await tmux.selectWindow(id: window.id) }
        saveUIState()
    }

    func addSession(name: String, path: String) async {
        await tmux.newSession(name: name, path: path)
        await refresh()
        if let session = workspace.sessions.first(where: { $0.name == name }) {
            selectSession(session)
        }
    }

    func removeSession(_ session: Session) {
        Task { await tmux.killSession(name: session.name) }
    }

    func addWindow(in session: Session) {
        Task { await tmux.newWindow(session: session.name, path: session.path) }
    }

    func removeWindow(_ window: Window) {
        Task { await tmux.killWindow(id: window.id) }
    }

    /// Removes a window, selecting the tab to its left (or the next tab if it was first).
    func removeWindow(_ window: Window, in session: Session) {
        if let index = session.windows.firstIndex(where: { $0.id == window.id }) {
            let nextIndex = index > 0 ? index - 1 : min(index + 1, session.windows.count - 1)
            if nextIndex != index, nextIndex < session.windows.count {
                selectWindow(session.windows[nextIndex])
            }
        }
        Task { await tmux.killWindow(id: window.id) }
    }

    func renameSession(_ session: Session, to name: String) {
        Task { await tmux.renameSession(target: session.name, newName: name) }
    }

    func renameWindow(_ window: Window, to name: String) {
        Task { await tmux.renameWindow(id: window.id, newName: name) }
    }

    /// Closes the current pane (like tmux prefix+x). Cascades:
    /// multiple panes → kill pane; one pane + multiple tabs → kill window; last tab → close project.
    /// Confirms if a process is running.
    func closeCurrentPane() {
        guard let session = workspace.activeSession,
              let windowId = workspace.activeWindowId,
              let window = session.windows.first(where: { $0.id == windowId })
        else { return }

        let activePane = window.panes.first(where: { $0.active }) ?? window.panes.first
        let hasMultiplePanes = window.panes.count > 1
        let hasMultipleWindows = session.windows.count > 1

        // Check if a non-shell process is running
        let isRunning = activePane?.status == .running

        if isRunning {
            let processName = window.name
            let alert = NSAlert()
            if hasMultiplePanes {
                alert.messageText = "Close this pane?"
                alert.informativeText = "\"\(processName)\" is running in this pane."
                alert.addButton(withTitle: "Close Pane")
            } else if hasMultipleWindows {
                alert.messageText = "Close this tab?"
                alert.informativeText = "\"\(processName)\" is running in this tab."
                alert.addButton(withTitle: "Close Tab")
            } else {
                alert.messageText = "Close project \"\(session.name)\"?"
                alert.informativeText = "\"\(processName)\" is running."
                alert.addButton(withTitle: "Close Project")
            }
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        } else {
            // Settings-based warnings when no process is running
            let config = ForgeConfigStore.shared.config.general
            if !hasMultiplePanes && !hasMultipleWindows && (config?.warnOnCloseProject ?? true) {
                let alert = NSAlert()
                alert.messageText = "Close project \"\(session.name)\"?"
                alert.informativeText = "This will close all tabs and remove the project from Forge."
                alert.addButton(withTitle: "Close Project")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            } else if !hasMultiplePanes && hasMultipleWindows && (config?.warnOnCloseTab ?? false) {
                let alert = NSAlert()
                alert.messageText = "Close tab \"\(window.name)\"?"
                alert.informativeText = "This tab will be closed."
                alert.addButton(withTitle: "Close Tab")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
        }

        if hasMultiplePanes, let pane = activePane {
            Task { await tmux.killPane(id: pane.id) }
        } else if hasMultipleWindows {
            removeWindow(window, in: session)
        } else {
            removeSession(session)
        }
    }

    func clearScrollback() {
        guard let paneId = workspace.activePaneId else { return }
        Task { await tmux.clearHistory(pane: paneId) }
    }

    func splitPane(direction: SplitDirection) {
        guard let windowId = workspace.activeWindowId else { return }
        Task { await tmux.splitWindow(id: windowId, direction: direction) }
    }

    func swapWindow(offset: Int) {
        guard let windowId = workspace.activeWindowId else { return }
        Task { await tmux.swapWindow(id: windowId, offset: offset) }
    }

    // MARK: - Private

    private func fetchGitBranch() async {
        guard let path = workspace.activeSession?.path else {
            gitBranch = nil
            return
        }
        let result: String? = await withCheckedContinuation { cont in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let branch = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: (branch?.isEmpty == false) ? branch : nil)
            } catch {
                cont.resume(returning: nil)
            }
        }
        gitBranch = result
    }

    private func ensureServer() async {
        let sessions = await tmux.listSessions()
        if sessions.isEmpty {
            // Clean up stale socket if a previous server crashed
            let socketPath = "/private/tmp/tmux-\(getuid())/forge"
            if FileManager.default.fileExists(atPath: socketPath) {
                try? FileManager.default.removeItem(atPath: socketPath)
                ForgeLog.log("[app] Removed stale tmux socket")
            }
            await tmux.newSession(name: "forge-default", path: NSHomeDirectory())
        }
    }

    private func handleEvent(_ event: String) {
        ForgeLog.log("[control] \(event)")

        if event.hasPrefix("%bell") {
            // %bell <window_id> — mark panes in that window as having bell, no refresh needed
            let parts = event.split(separator: " ")
            if parts.count >= 2 {
                let windowId = String(parts[1])
                var found = false
                for session in workspace.sessions {
                    if let window = session.windows.first(where: { $0.id == windowId }) {
                        for pane in window.panes {
                            pane.hasBell = true
                        }
                        found = true
                        break
                    }
                }
                if !found {
                    ForgeLog.log("[control] Bell event for unknown window: \(windowId)")
                }
            }
            return
        }

        // Structural events that require a state refresh
        let structuralPrefixes = [
            "%window-add", "%window-close", "%unlinked-window-close",
            "%layout-change",
            "%session-changed", "%session-renamed",
            "%window-renamed",
        ]
        let isStructural = structuralPrefixes.contains { event.hasPrefix($0) }

        if isStructural {
            scheduleRefresh()
        }
        // Informational events (%begin, %end, %error, %pane-mode-changed, etc.) — no action needed
    }

    private func scheduleRefresh() {
        if isRefreshing {
            needsRefreshAfterCurrent = true
            return
        }
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            isRefreshing = true
            await refresh()
            isRefreshing = false
            if needsRefreshAfterCurrent {
                needsRefreshAfterCurrent = false
                scheduleRefresh()
            }
        }
    }

    private func startPeriodicRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await refresh()
            }
        }
    }

    private func mergeSessionState(_ infos: [SessionInfo]) {
        var updated: [Session] = []
        for info in infos {
            if let existing = workspace.session(byId: info.id) {
                existing.name = info.name
                existing.windowCount = info.windowCount
                existing.attached = info.attached
                existing.path = info.path
                updated.append(existing)
            } else {
                updated.append(Session(id: info.id, name: info.name, windowCount: info.windowCount,
                                      attached: info.attached, path: info.path))
            }
        }
        workspace.sessions = updated
        if workspace.activeSessionId == nil, let first = workspace.sessions.first {
            workspace.activeSessionId = first.id
        }
    }

    private func mergeWindowState(session: Session, _ infos: [WindowInfo]) {
        var updated: [Window] = []
        for info in infos {
            if let existing = session.windows.first(where: { $0.id == info.id }) {
                existing.index = info.index
                existing.name = info.name
                existing.active = info.active
                updated.append(existing)
            } else {
                updated.append(Window(id: info.id, sessionId: info.sessionId,
                                     index: info.index, name: info.name, active: info.active))
            }
        }
        session.windows = updated
        if let active = infos.first(where: { $0.active }) {
            if session.id == workspace.activeSessionId {
                workspace.activeWindowId = active.id
            }
        }
    }

    // MARK: - UI State Persistence

    func saveUIState(sidebarVisible: Bool? = nil, expandedSessionNames: [String]? = nil) {
        let activeSession = workspace.sessions.first { $0.id == workspace.activeSessionId }
        let activeWindow = activeSession?.windows.first { $0.id == workspace.activeWindowId }

        ForgeConfigStore.shared.update { config in
            var state = config.uiState ?? ForgeConfig.UIState()
            state.activeSessionName = activeSession?.name
            state.activeWindowIndex = activeWindow?.index
            if let sidebarVisible { state.sidebarVisible = sidebarVisible }
            if let expandedSessionNames { state.expandedSessionNames = expandedSessionNames }
            config.uiState = state
        }
    }

    private func seedRecentDirectories() {
        let paths = workspace.sessions.compactMap { session -> String? in
            guard let path = session.path, !path.isEmpty, path != NSHomeDirectory() else { return nil }
            return path
        }
        guard !paths.isEmpty else { return }
        ForgeConfigStore.shared.update { config in
            for path in paths where !config.recentDirectories.contains(path) {
                config.recentDirectories.append(path)
            }
            if config.recentDirectories.count > 20 {
                config.recentDirectories = Array(config.recentDirectories.prefix(20))
            }
        }
    }

    private func restoreUIState() {
        guard let state = ForgeConfig.load().uiState else { return }

        // Restore active session by name
        if let name = state.activeSessionName,
           let session = workspace.sessions.first(where: { $0.name == name }) {
            workspace.activeSessionId = session.id
            Task { await tmux.switchClient(session: session.name) }

            // Restore active window by index within that session
            if let index = state.activeWindowIndex,
               let window = session.windows.first(where: { $0.index == index }) {
                workspace.activeWindowId = window.id
                Task { await tmux.selectWindow(id: window.id) }
            } else if let first = session.windows.first {
                workspace.activeWindowId = first.id
            }
        }
    }

    private func mergePaneState(window: Window, _ infos: [PaneInfo]) {
        var updated: [Pane] = []
        for info in infos {
            if let existing = window.panes.first(where: { $0.id == info.id }) {
                existing.index = info.index
                existing.active = info.active
                existing.currentCommand = info.currentCommand
                existing.currentPath = info.currentPath
                existing.width = info.width
                existing.height = info.height
                existing.pid = info.pid
                existing.status = existing.hasBell ? .needsAttention : PaneStatus.from(command: info.currentCommand)
                updated.append(existing)
            } else {
                updated.append(Pane(id: info.id, windowId: info.windowId, index: info.index,
                                   active: info.active, currentCommand: info.currentCommand,
                                   currentPath: info.currentPath, width: info.width,
                                   height: info.height, pid: info.pid))
            }
        }
        window.panes = updated
        if let active = infos.first(where: { $0.active }) {
            workspace.activePaneId = active.id
        }
    }
}
