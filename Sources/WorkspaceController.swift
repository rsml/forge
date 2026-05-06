import AppKit
import Foundation
import Observation
import ForgeCore

/// Orchestrates domain state, routes events, delegates commands to ports.
/// Views consume this via @Environment. Action methods live in WorkspaceController+Actions.
@Observable
@MainActor
final class WorkspaceController {
    let workspace = Workspace()
    var attentionManager: AttentionManager?
    let config: ForgeConfigStore
    let syncEngine: TmuxSyncEngine
    let tmux: any TmuxPort
    private let git: any GitPort
    private let uiState: UIStatePersistence
    var perProjectActiveTabId: [String: String] = [:]

    var gitBranch: String? { syncEngine.gitBranch }

    init(tmux: any TmuxPort, git: any GitPort, config: ForgeConfigStore) {
        self.tmux = tmux
        self.git = git
        self.config = config
        self.syncEngine = TmuxSyncEngine(workspace: workspace, tmux: tmux, git: git, config: config)
        self.uiState = UIStatePersistence(config: config)
    }

    // MARK: - Lifecycle

    func connect() {
        Task {
            ForgeLog.log("[app] Connecting...")
            await ensureServer()
            if let configPath = tmux.configPath {
                await tmux.sourceConfig(path: configPath)
            }
            syncEngine.attentionManager = attentionManager
            syncEngine.setPostRefreshHook { [weak self] in
                guard let self else { return }
                await self.attentionManager?.scanForContentMatches(
                    workspace: self.workspace, tmux: self.tmux
                )
            }
            await syncEngine.refresh()
            uiState.seedRecentDirectories(from: workspace)
            uiState.restore(workspace: workspace, tmux: tmux)
            let allUUIDs = Set(workspace.projects.flatMap { $0.tabs.map(\.uuid) })
            attentionManager?.pruneStaleHiddenEntries(validUUIDs: allUUIDs)

            tmux.startControlMode { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(event)
                }
            }

            syncEngine.start()
            workspace.connected = true
            ForgeLog.log("[app] Connected. \(workspace.projects.count) sessions found.")
        }
    }

    func disconnect() {
        syncEngine.stop()
        tmux.stopControlMode()
    }

    // MARK: - UI State

    func saveUIState(sidebarVisible: Bool? = nil, expandedProjectNames: [String]? = nil) {
        uiState.save(workspace: workspace, sidebarVisible: sidebarVisible, expandedProjectNames: expandedProjectNames)
    }

    // MARK: - Private

    private func ensureServer() async {
        let sessions = await tmux.listProjects()
        if sessions.isEmpty {
            let socketPath = "/private/tmp/tmux-\(getuid())/forge"
            if FileManager.default.fileExists(atPath: socketPath) {
                try? FileManager.default.removeItem(atPath: socketPath)
                ForgeLog.log("[app] Removed stale tmux socket")
            }
            await tmux.newProject(name: "forge-default", path: NSHomeDirectory())
        }
    }

    private func handleEvent(_ rawEvent: String) {
        ForgeLog.log("[control] \(rawEvent)")

        let event = TmuxEventParser.parse(rawEvent)
        switch event {
        case .bell(let tabId):
            if let (_, tab) = workspace.findTab(byTmuxId: tabId) {
                for pane in tab.panes { pane.hasBell = true }
                attentionManager?.handleEvent(.bell(tabUUID: tab.uuid))
            } else {
                ForgeLog.log("[control] Bell event for unknown tab: \(tabId)")
            }

        case .tabClose(let tabId):
            if let (_, tab) = workspace.findTab(byTmuxId: tabId) {
                attentionManager?.removeTab(tab.uuid)
            }
            syncEngine.scheduleRefresh()

        case .structural:
            syncEngine.scheduleRefresh()

        case .ignored:
            break
        }
    }
}
