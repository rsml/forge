import AppKit
import Foundation
import ForgeCore

/// Browser-pane wiring: bridges BrowserRenderer KVO callbacks to BrowserState
/// on the Pane model, routes web-page navigation intents, and handles the
/// bidirectional Terminal ↔ Browser convert flow.
extension WorkspaceController {

    /// Convert a terminal pane in place to a browser pane. pane.id is preserved;
    /// only `content` and the renderer change. If a foreground process is running,
    /// shows an HIG-compliant confirmation sheet first (matches the close-pane pattern).
    @MainActor
    func convertToBrowser(pane: Pane) {
        Task { @MainActor in
            let activities: [PaneActivity] = await {
                if let port = activityPort { return await port.query(paneIds: [pane.id]) }
                return []
            }()
            let active = activities.first(where: { $0.isActive })

            let proceed: Bool
            if let active {
                let cmd = active.command ?? "a process"
                proceed = await confirmConvert(
                    message: "Converting this pane to a browser will terminate \"\(cmd)\".",
                    actionLabel: "Convert to Browser"
                )
            } else {
                proceed = true
            }

            guard proceed else { return }
            doConvertToBrowser(pane: pane)
        }
    }

    /// Convert a browser pane in place to a terminal pane. pane.id is preserved;
    /// only `content` and the renderer change. If the browser has a loaded URL,
    /// shows a confirmation sheet first.
    @MainActor
    func convertToTerminal(pane: Pane) {
        Task { @MainActor in
            let hasURL = pane.browserState?.url != nil

            let proceed: Bool
            if hasURL {
                proceed = await confirmConvert(
                    message: "Converting this pane to a terminal will discard the current page.",
                    actionLabel: "Convert to Terminal"
                )
            } else {
                proceed = true
            }

            guard proceed else { return }
            doConvertToTerminal(pane: pane)
        }
    }

    /// Tear down the terminal renderer + daemon fd, swap content, spin up
    /// a fresh browser renderer.
    @MainActor
    private func doConvertToBrowser(pane: Pane) {
        // Tear down terminal: drop renderer (deinits GhosttyRenderer → closes
        // its surface), detach from activity watcher, release daemon fd
        // (kills the shell — that's the contract of "terminate the process").
        paneRenderers.removeValue(forKey: pane.id)
        paneActivityWatcher?.paneRemoved(pane.id)
        if let daemon = daemonAdapter {
            let paneId = pane.id
            Task { try? await daemon.release(paneId: paneId) }
        }

        // Swap content. pane.id and the SplitNode are untouched.
        pane.content = .browser(BrowserState())

        // Stand up the browser renderer.
        let renderer = WebKitBrowserRenderer()
        wireBrowserCallbacks(renderer: renderer, pane: pane)
        paneRenderers[pane.id] = renderer

        ForgeLog.log("[browser] Converted pane \(pane.id) → browser")

        // Persist the new pane kind.
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)

        // Auto-open the URL palette so the user can navigate immediately.
        appState?.openURLPalette(for: pane)
    }

    /// Tear down the browser renderer, swap content, spawn a fresh shell
    /// via the standard EXEC + daemon path.
    @MainActor
    private func doConvertToTerminal(pane: Pane) {
        // Tear down browser: dropping the renderer deinits WKWebView.
        paneRenderers.removeValue(forKey: pane.id)

        // Determine the new shell's cwd — prefer the active project's path.
        let cwd = workspace.activeProject?.path ?? NSHomeDirectory()

        // Swap content. pane.id and the SplitNode are untouched.
        pane.content = .terminal(TerminalState(currentPath: cwd))

        // Create the EXEC renderer + daemon register, mirroring addTab /
        // addProject's pattern of creating the renderer BEFORE the next
        // SwiftUI render to avoid a frame with no renderer (flash).
        let renderer = createExecRenderer(for: pane, cwd: cwd)
        paneRenderers[pane.id] = renderer
        scheduleDaemonRegister(paneId: pane.id, cwd: cwd)

        ForgeLog.log("[browser] Converted pane \(pane.id) → terminal (cwd: \(cwd))")

        // Persist the new pane kind.
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
    }

    /// Reuses `CloseConfirmation.present` so the convert sheet looks identical
    /// to the close-pane sheet: destructive button red, Cancel as default,
    /// presented as a window sheet rather than a free-floating alert.
    @MainActor
    private func confirmConvert(message: String, actionLabel: String) async -> Bool {
        guard let window = NSApp.mainWindow else { return true }
        let info = CloseConfirmation.AlertInfo(
            message: message,
            info: "",
            action: actionLabel
        )
        return await CloseConfirmation.present(info, in: window)
    }

    /// Bidirectional wiring between a BrowserRenderer and its Pane's BrowserState.
    /// Updates to `pane.browserState` flow from the renderer's KVO observers via these callbacks.
    @MainActor
    func wireBrowserCallbacks(renderer: any BrowserRenderer, pane: Pane) {
        renderer.onURLChange = { [weak self, weak pane] url in
            pane?.browserState?.url = url
            // Debounced save so the last URL survives a quit. Fires ~1s after
            // the user finishes navigating, not on every redirect/progress tick.
            self?.scheduleSaveWorkspace()
        }
        renderer.onTitleChange = { [weak pane] title in
            pane?.browserState?.pageTitle = title
        }
        renderer.onLoadingChange = { [weak pane] loading in
            pane?.browserState?.isLoading = loading
        }
        renderer.onProgress = { [weak pane] progress in
            pane?.browserState?.loadingProgress = progress
        }
        renderer.onFaviconChange = { [weak pane] data in
            pane?.browserState?.faviconData = data
        }
        renderer.onCanGoBackChange = { [weak pane] canGoBack in
            pane?.browserState?.canGoBack = canGoBack
        }
        renderer.onCanGoForwardChange = { [weak pane] canGoForward in
            pane?.browserState?.canGoForward = canGoForward
        }
        renderer.onLoadError = { [weak pane] error in
            // For now: just clear loading state. Task 14 will surface this to UI.
            pane?.browserState?.isLoading = false
            ForgeLog.log("[browser] load error: \(error.localizedDescription)")
        }
        renderer.onNavigationRequest = { [weak self, weak pane] intent in
            guard let pane else { return }
            self?.handleNavigationIntent(intent, sourcePane: pane)
        }
        // Track which browser pane is focused so ⌘L / ⌘F / ⌘[ / ⌘] target the
        // pane the user just clicked into, even when the WKWebView holds focus.
        let paneId = pane.id
        renderer.onFocusGained = { [weak self] in
            self?.lastFocusedPaneId = paneId
        }
    }

    /// Routes web-page navigation intents (target=_blank, window.open(), ⌘+click).
    @MainActor
    func handleNavigationIntent(_ intent: NavigationIntent, sourcePane: Pane) {
        switch intent {
        case .sameTabBlank(let url):
            // Replace current pane URL.
            (paneRenderers[sourcePane.id] as? any BrowserRenderer)?.loadURL(url)

        case .modifierNewPane(let url):
            // ⌘+click → split right with a new browser pane, preloaded with the URL.
            // splitPaneNativePTY sets lastFocusedPaneId to the new pane's id, so we
            // can look it up directly rather than relying on tab ordering heuristics.
            splitPaneNativePTY(direction: .horizontal, as: .browser)
            guard let newPaneId = lastFocusedPaneId,
                  let newRenderer = paneRenderers[newPaneId] as? any BrowserRenderer
            else { return }
            newRenderer.loadURL(url)
            // splitPaneNativePTY auto-opens the URL palette for new browser panes;
            // suppress it here since the URL is already known.
            appState?.closeURLPalette()

        case .popupWindow(let url, let size):
            let popup = BrowserPopupWindow(url: url, size: size ?? NSSize(width: 600, height: 700))
            popup.show()
        }
    }

    // MARK: - Port Detection

    /// Scan sibling terminal panes in this tab for dev-server ports.
    /// Reads scrollback log files (written by GhosttyRenderer) for ~256KB of
    /// recent output per pane. Falls back to `currentCommand` for panes that
    /// don't have a log yet (e.g. newly-created in this session before the
    /// reconnect path runs). Pure pass over text → `PortDetector`.
    @MainActor
    func detectedPortsForTab(_ tab: Tab) -> [DetectedPort] {
        var combined = ""
        for pane in tab.panes where pane.kind == .terminal {
            // Best-effort scrollback read.
            let logPath = NSHomeDirectory() + "/.config/forge/scrollback/\(pane.id).log"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
               let text = String(data: data, encoding: .utf8) {
                combined += text + "\n"
            } else if let cmd = pane.terminalState?.currentCommand, !cmd.isEmpty {
                combined += cmd + "\n"
            }
        }
        return PortDetector.detect(in: combined)
    }

    /// Currently focused pane if it's a browser, else nil. Used by ⌘L menu binding.
    var focusedBrowserPane: Pane? {
        guard let pane = focusedPane, pane.kind == .browser else { return nil }
        return pane
    }

    // MARK: - New Browser Tab

    /// Create a new tab containing a single browser pane. Mirrors
    /// `addTabNativePTY` for terminal tabs (see WorkspaceController+Actions)
    /// but skips the PTY / daemon path. Auto-opens the URL palette so the
    /// user can navigate immediately.
    @MainActor
    func addBrowserTab(in project: Project) {
        guard config.isNativePTY else {
            ForgeLog.log("[app] Browser tab requires native PTY mode — ignoring")
            return
        }
        addBrowserTabNativePTY(in: project)
    }

    @MainActor
    private func addBrowserTabNativePTY(in project: Project) {
        let tabId = UUID().uuidString
        let tab = Tab(id: tabId, projectId: project.id, index: project.tabs.count, name: "Browser")
        let paneId = UUID().uuidString
        let pane = Pane.browser(id: paneId, tabId: tabId)
        tab.panes.append(pane)
        project.tabs.append(tab)

        // Create renderer BEFORE selectTab triggers SwiftUI render — prevents flash
        let renderer = WebKitBrowserRenderer()
        wireBrowserCallbacks(renderer: renderer, pane: pane)
        paneRenderers[paneId] = renderer

        selectTab(tab)
        ForgeLog.log("[app] Added browser tab in \(project.name) (native PTY)")

        // Auto-open the URL palette so the user can navigate immediately.
        appState?.openURLPalette(for: pane)
    }
}
