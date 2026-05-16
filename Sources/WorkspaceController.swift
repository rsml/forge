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
    var attentionManager: (any AttentionPort)?
    var notifier: (any NotificationPort)?
    let config: ForgeConfigStore
    let toastState: NotificationToastState
    let syncEngine: TmuxSyncEngine
    let tmux: any TmuxPort
    private let uiState: UIStatePersistence
    var perProjectActiveTabId: [String: String] = [:]
    /// Set before intentionally stopping control mode (e.g. removing last project) to suppress reconnect toast.
    var expectingDisconnect = false
    let outputRouter = OutputRouter()
    /// One renderer per live pane. Keyed by pane ID. Triggers SwiftUI updates.
    var paneRenderers: [String: any TerminalRenderer] = [:]
    /// Ghostty app instance for native rendering. Nil when using SwiftTerm fallback.
    var ghosttyApp: GhosttyApp?

    var gitBranch: String? { syncEngine.gitBranch }

    init(tmux: any TmuxPort, config: ForgeConfigStore, toastState: NotificationToastState) {
        self.tmux = tmux
        self.config = config
        self.toastState = toastState
        self.syncEngine = TmuxSyncEngine(workspace: workspace, tmux: tmux, config: config)
        self.uiState = UIStatePersistence(config: config)
    }

    // MARK: - Lifecycle

    func connect() {
        Task {
            ForgeLog.log("[app] Connecting...")
            cleanStaleSocket()
            if let configPath = tmux.configPath {
                await tmux.sourceConfig(path: configPath)
            }
            syncEngine.setPostRefreshHook { [weak self] events in
                guard let self else { return }
                for event in events {
                    switch event {
                    case .bell(let tabUUID):
                        self.attentionManager?.handleEvent(.bell(tabUUID: tabUUID))
                        self.sendAttentionNotification(tabUUID: tabUUID)
                    case .silenceCleared(let tabUUID):
                        self.attentionManager?.markDone(tabUUID)
                    case .commandCompleted(let tabUUID):
                        self.attentionManager?.handleEvent(.commandCompleted(tabUUID: tabUUID))
                        self.sendAttentionNotification(tabUUID: tabUUID)
                    case .contentMatch(let tabUUID):
                        self.attentionManager?.handleEvent(.contentMatch(tabUUID: tabUUID))
                        self.sendAttentionNotification(tabUUID: tabUUID)
                    }
                }
                // Sync renderers with current pane state — creates renderers for
                // new panes (splits), removes stale ones (closed panes).
                self.updateRenderers()
            }
            await syncEngine.refresh()
            uiState.seedRecentDirectories(from: workspace)
            uiState.restore(workspace: workspace, tmux: tmux)
            let allUUIDs = Set(workspace.projects.flatMap { $0.tabs.map(\.uuid) })
            attentionManager?.pruneStaleHiddenEntries(validUUIDs: allUUIDs)

            if workspace.projects.isEmpty {
                expectingDisconnect = true
            } else {
                startControlMode()
            }

            NotificationCenter.default.addObserver(
                forName: .forgeNavigateToTab, object: nil, queue: .main
            ) { [weak self] note in
                guard let self,
                      let uuid = note.userInfo?["tabUUID"] as? UUID,
                      let (project, tab) = self.workspace.findTab(byUUID: uuid) else { return }
                self.navigateToTab(tab, in: project)
                NSApp.activate()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .forgeFocusTerminal, object: nil)
                }
            }

            // Seed native renderers for the active project's panes after initial sync
            if config.isNativePaneRendering {
                updateRenderers()
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

    func startControlMode() {
        // Set native rendering flag on the adapter before starting control mode
        if let adapter = tmux as? TmuxAdapter {
            adapter.nativeRendering = config.isNativePaneRendering
        }

        var outputHandler: (@Sendable (String, Data) -> Void)?
        if config.isNativePaneRendering {
            outputHandler = { [weak self] paneId, data in
                Task { @MainActor in
                    self?.outputRouter.route(paneId: paneId, data: data)
                }
            }
        }

        tmux.startControlMode(
            onEvent: { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(event)
                }
            },
            onOutput: outputHandler,
            onDisconnect: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if self.expectingDisconnect {
                        self.expectingDisconnect = false
                        // Workspace still has the removed project (sync hasn't run yet).
                        // count <= 1 means the last project was removed — clean up.
                        if self.workspace.projects.count <= 1 {
                            self.workspace.projects.removeAll()
                            self.workspace.activeProjectId = nil
                            self.workspace.activeTabId = nil
                            self.tmux.stopControlMode()
                        }
                        // Non-last: suppress toast, control mode will reconnect.
                        return
                    }
                    self.toastState.show(
                        title: "Connection lost",
                        message: "Reconnecting to tmux...",
                        icon: "exclamationmark.triangle.fill",
                        duration: 300
                    )
                }
            },
            onReconnect: { [weak self] in
                Task { @MainActor in
                    self?.toastState.dismiss()
                }
            }
        )
    }

    // MARK: - UI State

    func saveUIState(sidebarVisible: Bool? = nil, expandedProjectNames: [String]? = nil) {
        uiState.save(workspace: workspace, sidebarVisible: sidebarVisible, expandedProjectNames: expandedProjectNames)
    }

    // MARK: - Private

    private func cleanStaleSocket() {
        let socketPath = "/private/tmp/tmux-\(getuid())/forge"
        let sessions = (try? FileManager.default.contentsOfDirectory(atPath: "/private/tmp/tmux-\(getuid())")) ?? []
        if sessions.isEmpty, FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
            ForgeLog.log("[app] Removed stale tmux socket")
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

        case .silenceChanged(let tabId, let isSilent):
            // Only react to silence onset — show dot instantly for running panes.
            // Clearing is handled by the poll cycle checking window_activity freshness,
            // which naturally ignores brief touches from tab selection.
            if isSilent, let (_, tab) = workspace.findTab(byTmuxId: tabId) {
                let alreadyHadBell = tab.panes.contains(where: \.hasBell)
                for pane in tab.panes where pane.status == .running { pane.hasBell = true }
                if tab.panes.contains(where: { $0.status == .running }) {
                    attentionManager?.handleEvent(.bell(tabUUID: tab.uuid))
                    if !alreadyHadBell {
                        sendAttentionNotification(tabUUID: tab.uuid)
                    }
                }
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
