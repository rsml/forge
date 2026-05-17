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
    /// Total terminal area frame size (set by TerminalArea via GeometryReader).
    var terminalAreaSize: CGSize = .zero
    /// Terminal cell size in points (width, height). Computed from the first
    /// renderer that reports cols/rows. Used by PaneSplitView for divider width
    /// so SwiftUI's pixel allocation matches tmux's cell-based layout exactly.
    var terminalCellSize: CGSize = .zero
    /// When true, resize flush is deferred until drag ends.
    var suppressPaneResize = false
    var pendingResizes: [String: (cols: Int, rows: Int)] = [:]
    var resizeFlushWork: DispatchWorkItem?
    /// Set true after divider drag — flushPendingResizes sends resize-pane
    /// to apply the user's proportions. On startup, only resize-window is
    /// sent (tmux proportionally scales, preserving stored ratios).
    var sendResizePaneOnFlush = false
    /// Ghostty app instance for native rendering.
    var ghosttyApp: GhosttyApp?
    /// Process adapter for native PTY mode. Nil when using tmux IO.
    var processAdapter: ProcessAdapter?
    /// Daemon adapter for PTY fd persistence. Nil when using tmux.
    var daemonAdapter: DaemonAdapter?
    /// Last focused pane ID — set by GhosttyNSView.onFocusGained.
    /// Used by splitPane to know which pane to split (firstResponder
    /// changes when clicking toolbar buttons).
    var lastFocusedPaneId: String?

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
        if config.isNativePTY {
            connectNativePTY()
            return
        }
        connectTmux()
    }

    /// Native PTY connect: load workspace from JSON, no tmux.
    private func connectNativePTY() {
        Task {
            ForgeLog.log("[app] Connecting (native PTY mode)...")

            // Load workspace structure from disk
            if let persisted = WorkspacePersistence.load() {
                for pp in persisted.projects {
                    let project = Project(id: pp.id, name: pp.name, path: pp.path)
                    for pt in pp.tabs {
                        let tab = Tab(id: pt.id, projectId: pp.id, index: project.tabs.count, name: pt.name)
                        for pPane in pt.panes {
                            let pane = Pane(id: pPane.id, tabId: pt.id, currentPath: pPane.cwd)
                            tab.panes.append(pane)
                        }
                        // Restore split tree (directions, nesting, proportions)
                        if let persistedTree = pt.splitTree {
                            tab.splitTree = WorkspacePersistence.decodeSplitNode(persistedTree)
                        }
                        project.tabs.append(tab)
                    }
                    workspace.projects.append(project)
                }
                workspace.activeProjectId = persisted.activeProjectId
                workspace.activeTabId = persisted.activeTabId

                // Restore window frame and fullscreen state
                DispatchQueue.main.async {
                    if let window = NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) {
                        if let f = persisted.windowFrame {
                            window.setFrame(NSRect(x: f.x, y: f.y, width: f.width, height: f.height), display: true)
                        }
                        if persisted.fullscreen == true, !window.styleMask.contains(.fullScreen) {
                            window.toggleFullScreen(nil)
                        }
                    }
                }

                ForgeLog.log("[app] Loaded \(workspace.projects.count) projects from workspace.json")
            }

            // If no persisted workspace, create a default project
            if workspace.projects.isEmpty {
                let id = UUID().uuidString
                let project = Project(id: id, name: "default", path: NSHomeDirectory())
                let tabId = UUID().uuidString
                let tab = Tab(id: tabId, projectId: id, index: 0, name: "zsh")
                let paneId = UUID().uuidString
                let pane = Pane(id: paneId, tabId: tabId, currentPath: NSHomeDirectory())
                tab.panes.append(pane)
                project.tabs.append(tab)
                workspace.projects.append(project)
                workspace.activeProjectId = id
                workspace.activeTabId = tabId
                ForgeLog.log("[app] Created default project")
            }

            // Pre-fetch daemon fds BEFORE creating renderers.
            // This prevents the race where updateRenderers creates EXEC surfaces
            // that get replaced by EXTERNAL_FD surfaces 40s later.
            if let daemon = daemonAdapter {
                let allPanes = workspace.projects.flatMap { $0.tabs.flatMap { $0.panes } }
                for pane in allPanes {
                    if let result = try? await daemon.retrieve(paneId: pane.id) {
                        guard let ghosttyApp else { continue }
                        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, fd: result.fd)
                        renderer.configureForReconnect(paneId: pane.id, pid: result.pid)
                        renderer.nsView.onFocusGained = { [weak self] in
                            self?.lastFocusedPaneId = pane.id
                        }
                        paneRenderers[pane.id] = renderer
                        ForgeLog.log("[daemon] Pre-fetched pane \(pane.id) (fd=\(result.fd))")
                    }
                }
            }

            updateRenderers()
            workspace.connected = true
            ForgeLog.log("[app] Connected (native PTY). \(workspace.projects.count) projects.")
        }
    }

    /// Legacy tmux connect flow.
    private func connectTmux() {
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
            let allUUIDs = Set(workspace.projects.flatMap { $0.tabs.map(\.uuid) })
            attentionManager?.pruneStaleHiddenEntries(validUUIDs: allUUIDs)

            // Detach stale clients BEFORE starting control mode.
            // Must happen before any controlModeSend calls (including
            // uiState.restore which sends select-tab/switch-client).
            if let adapter = tmux as? TmuxAdapter {
                await adapter.detachAllClients()
            }

            if workspace.projects.isEmpty {
                expectingDisconnect = true
            } else {
                startControlMode()
            }

            // Restore UI state AFTER control mode is running so commands aren't dropped.
            uiState.restore(workspace: workspace, tmux: tmux)

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

            // Seed native renderers for the active project's panes after initial sync.
            // switchClient ensures the control mode client is on the active session
            // before renderers fire resize commands.
            if config.isNativePaneRendering {
                if let project = workspace.activeProject {
                    await tmux.switchClient(project: project.name)
                }
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
                ForgeLog.log("[debug] %output \(paneId): \(data.count) bytes")
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
