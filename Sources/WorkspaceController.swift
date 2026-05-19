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
    /// Cross-feature UI state. Wired by AppDelegate after AppState is built.
    /// Used by browser-pane creation paths to auto-open the URL palette.
    weak var appState: AppState?
    let config: ForgeConfigStore
    let toastState: NotificationToastState
    private let uiState: UIStatePersistence
    var perProjectActiveTabId: [String: String] = [:]
    /// One renderer per live pane. Keyed by pane ID. Triggers SwiftUI updates.
    var paneRenderers: [String: any PaneRenderer] = [:]
    /// Total terminal area frame size (set by TerminalArea via GeometryReader).
    var terminalAreaSize: CGSize = .zero
    /// Terminal cell size in points (width, height). Computed from the first
    /// renderer that reports cols/rows. Used by PaneSplitView for divider width.
    var terminalCellSize: CGSize = .zero
    /// When true, resize flush is deferred until drag ends.
    var suppressPaneResize = false
    var pendingResizes: [String: (cols: Int, rows: Int)] = [:]
    var resizeFlushWork: DispatchWorkItem?
    /// Ghostty app instance for native rendering.
    var ghosttyApp: GhosttyApp?
    /// Daemon adapter for PTY fd persistence.
    var daemonAdapter: DaemonAdapter?
    /// Last focused pane ID — set by GhosttyNSView.onFocusGained.
    /// Used by splitPane to know which pane to split (firstResponder
    /// changes when clicking toolbar buttons).
    var lastFocusedPaneId: String?

    /// Foreground-process activity check for close-confirmation prompts.
    /// Set by AppDelegate after the daemon adapter is created.
    var activityPort: (any PaneActivityPort)?

    /// Detects bell, content-match, and command-completed events from PTY
    /// output and daemon activity polls. Hooked into every renderer's
    /// onOutput callback.
    var paneActivityWatcher: PaneActivityWatcher?

    /// Active project's git branch.
    let gitBranchPoller = GitBranchPoller()

    var gitBranch: String? { gitBranchPoller.branch }

    init(config: ForgeConfigStore, toastState: NotificationToastState) {
        self.config = config
        self.toastState = toastState
        self.uiState = UIStatePersistence(config: config)
    }

    // MARK: - Lifecycle

    func connect() {
        // Stand up the attention watcher before we start creating renderers
        // so it can be wired into onOutput callbacks from the first byte.
        if let activity = activityPort {
            let watcher = PaneActivityWatcher(workspace: workspace, activity: activity, config: config)
            watcher.onEvent = { [weak self] event in
                guard let self else { return }
                self.attentionManager?.handleEvent(event)
                self.sendAttentionNotification(tabUUID: event.tabUUID)
                if self.config.isStackMode {
                    let activeUUIDs = Set(
                        self.workspace.projects
                            .flatMap(\.tabs)
                            .filter(\.needsAttention)
                            .map(\.uuid)
                    )
                    self.attentionManager?.pruneResolved(activeAttentionUUIDs: activeUUIDs)
                }
            }
            paneActivityWatcher = watcher
        }

        Task {
            ForgeLog.log("[app] Connecting...")

            // Load workspace structure from disk
            if let persisted = WorkspacePersistence.load() {
                for pp in persisted.projects {
                    let project = Project(id: pp.id, name: pp.name, path: pp.path)
                    for pt in pp.tabs {
                        let tab = Tab(id: pt.id, projectId: pp.id, index: project.tabs.count, name: pt.name)
                        for pPane in pt.panes {
                            let pane: Pane
                            switch pPane.content ?? .terminal {
                            case .browser(let urlString):
                                let url = urlString.flatMap { URL(string: $0) }
                                pane = Pane.browser(id: pPane.id, tabId: pt.id, url: url)
                                // Browser panes don't go through the daemon/EXEC reconnect path —
                                // create the renderer + wire callbacks here so they're ready when
                                // updateRenderers() runs at the end of connectNativePTY().
                                let renderer = WebKitBrowserRenderer()
                                wireBrowserCallbacks(renderer: renderer, pane: pane)
                                paneRenderers[pane.id] = renderer
                                if let url { renderer.loadURL(url) }
                            case .terminal:
                                pane = Pane(id: pPane.id, tabId: pt.id, currentPath: pPane.cwd)
                            }
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

            // Empty workspace — user can add projects via the UI.

            // Pre-fetch daemon fds BEFORE creating renderers.
            // This prevents the race where updateRenderers creates EXEC surfaces
            // that get replaced by EXTERNAL_FD surfaces 40s later.
            if let daemon = daemonAdapter {
                // Only terminal panes had a daemon fd to persist. Browser panes
                // are handled in the project/tab loader above (renderer created
                // synchronously and URL loaded).
                let allPanes = workspace.projects.flatMap { $0.tabs.flatMap { $0.panes } }
                                                 .filter { $0.kind == .terminal }
                for pane in allPanes {
                    if let result = try? await daemon.retrieve(paneId: pane.id) {
                        guard let ghosttyApp else { continue }
                        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, fd: result.fd)
                        renderer.diagnosticPaneId = pane.id
                        renderer.configureForReconnect(paneId: pane.id, pid: result.pid)
                        let paneId = pane.id
                        renderer.nsView.onFocusGained = { [weak self] in
                            self?.lastFocusedPaneId = paneId
                        }
                        renderer.onOutput = { [weak self] data in
                            self?.paneActivityWatcher?.processOutput(paneId: paneId, data: data)
                        }
                        renderer.onUserInput = { [weak self] in
                            guard let self,
                                  let found = self.workspace.findTab(byPaneId: paneId) else { return }
                            self.clearAttention(tab: found.tab)
                        }
                        paneRenderers[pane.id] = renderer
                        ForgeLog.log("[daemon] Pre-fetched pane \(pane.id) (fd=\(result.fd))")
                    }
                }
            }

            updateRenderers()
            paneActivityWatcher?.start()
            gitBranchPoller.start(workspace: workspace)
            workspace.connected = true
            ForgeLog.log("[app] Connected. \(workspace.projects.count) projects.")

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
        }
    }

    func disconnect() {
        paneActivityWatcher?.stop()
        gitBranchPoller.stop()
    }

    // MARK: - UI State

    func saveUIState(sidebarVisible: Bool? = nil, expandedProjectNames: [String]? = nil) {
        uiState.save(workspace: workspace, sidebarVisible: sidebarVisible, expandedProjectNames: expandedProjectNames)
    }

    // MARK: - Workspace persistence

    /// Debounced workspace.json save. Used by high-frequency change sources
    /// (e.g. browser URL updates during page navigation) to batch writes —
    /// the most recent state lands ~1s after the last change.
    private var saveDebounceTask: Task<Void, Never>?

    @MainActor
    func scheduleSaveWorkspace() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            let frame = NSApp.mainWindow?.frame
            WorkspacePersistence.save(workspace: self.workspace, windowFrame: frame)
        }
    }
}
