import Foundation
import Observation

/// Orchestrates domain state and tmux adapter.
/// Single @Observable object that all views consume.
@Observable
@MainActor
final class WorkspaceController {
    let workspace = Workspace()
    private let tmux: any TmuxPort
    private var refreshTask: Task<Void, Never>?

    init(tmux: any TmuxPort) {
        self.tmux = tmux
    }

    func connect() {
        Task {
            ForgeLog.log("[app] Connecting...")
            await ensureServer()
            await refresh()

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
        mergeSessionState(sessionInfos)

        for session in workspace.sessions {
            let windowInfos = await tmux.listWindows(session: session.name)
            mergeWindowState(session: session, windowInfos)

            for window in session.windows {
                let paneInfos = await tmux.listPanes(window: window.id)
                mergePaneState(window: window, paneInfos)
            }
        }
    }

    // MARK: - Actions

    func selectSession(_ session: Session) {
        workspace.activeSessionId = session.id
        if let window = session.windows.first(where: { $0.active }) ?? session.windows.first {
            workspace.activeWindowId = window.id
        }
        Task { await tmux.switchClient(session: session.name) }
    }

    func selectWindow(_ window: Window) {
        workspace.activeWindowId = window.id
        Task { await tmux.selectWindow(id: window.id) }
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

    func renameSession(_ session: Session, to name: String) {
        Task { await tmux.renameSession(target: session.name, newName: name) }
    }

    func renameWindow(_ window: Window, to name: String) {
        Task { await tmux.renameWindow(id: window.id, newName: name) }
    }

    // MARK: - Private

    private func ensureServer() async {
        let sessions = await tmux.listSessions()
        if sessions.isEmpty {
            await tmux.newSession(name: "forge-default", path: NSHomeDirectory())
        }
    }

    private func handleEvent(_ event: String) {
        ForgeLog.log("[control] \(event)")
        Task { await refresh() }
    }

    private func startPeriodicRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
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
