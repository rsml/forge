import AppKit
import ForgeCore

/// Native pane rendering: renderer creation, lifecycle, and daemon registration.
extension WorkspaceController {

    /// Creates an EXEC mode renderer — Ghostty owns the PTY directly.
    func createExecRenderer(for pane: Pane, cwd: String) -> any TerminalRenderer {
        guard let ghosttyApp else { fatalError("createExecRenderer requires ghosttyApp") }
        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, cwd: cwd)
        let paneId = pane.id
        renderer.nsView.onFocusGained = { [weak self] in
            self?.lastFocusedPaneId = paneId
        }
        renderer.onOutput = { [weak self] data in
            self?.paneActivityWatcher?.processOutput(paneId: paneId, data: data)
        }
        return renderer
    }

    /// Schedule a daemon registration for a freshly-created pane.
    ///
    /// The PTY master fd isn't available immediately after Ghostty surface
    /// creation, so we wait briefly before reading `ptyFD` / `foregroundPID`
    /// and calling `daemon.store`. After this completes, the daemon knows the
    /// pane and `is_active` queries will work — required for close confirmation
    /// to fire on tabs/projects added at runtime.
    ///
    /// Without this, splits register (they're created inside `updateRenderers`
    /// which already does this) but new tabs / new projects don't — they create
    /// the renderer directly in `addTabNativePTY` / `addProjectNativePTY` and
    /// skip the registration path. That asymmetry was the cause of cmd+W
    /// closing a new tab without prompting even when a process was running.
    @MainActor
    func scheduleDaemonRegister(paneId: String, cwd: String) {
        guard let daemon = daemonAdapter else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self,
                  let ghostty = self.paneRenderers[paneId] as? GhosttyRenderer
            else { return }
            let fd = ghostty.ptyFD
            guard fd >= 0 else {
                ForgeLog.log("[daemon] Pane \(paneId) — ptyFD unavailable, skipping store")
                return
            }
            let pid = ghostty.foregroundPID
            Task {
                try? await daemon.store(paneId: paneId, fd: fd, pid: pid, cwd: cwd)
                ForgeLog.log("[daemon] Stored fd=\(fd) for pane \(paneId)")
            }
        }
    }

    /// Synchronizes renderers with the active tab's panes. Creates renderers
    /// for newly-added panes (reconnecting via daemon if a stored fd exists,
    /// otherwise spawning a fresh EXEC shell). Keeps inactive-project
    /// renderers alive — destroying them would close the PTY master fd and
    /// kill the shell.
    func updateRenderers() {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else {
            paneRenderers.removeAll()
            return
        }

        let allPaneIds = Set(workspace.projects.flatMap { $0.tabs.flatMap { $0.panes.map(\.id) } })
        for id in paneRenderers.keys where !allPaneIds.contains(id) {
            paneRenderers.removeValue(forKey: id)
        }

        let activePaneIds = Set(tab.panes.map(\.id))

        var panesToCreate: [(pane: Pane, cwd: String)] = []
        for pane in tab.panes where paneRenderers[pane.id] == nil {
            let cwd = pane.currentPath.isEmpty ? (project.path ?? NSHomeDirectory()) : pane.currentPath
            panesToCreate.append((pane, cwd))
        }

        if !panesToCreate.isEmpty, let daemon = daemonAdapter {
            // Try daemon reconnect for ALL panes in a single Task
            // to avoid race conditions with concurrent updateRenderers calls.
            let paneIds = panesToCreate.map { ($0.pane.id, $0.cwd) }
            Task {
                for (paneId, cwd) in paneIds {
                    if await MainActor.run(body: { paneRenderers[paneId] != nil }) { continue }

                    if let result = try? await daemon.retrieve(paneId: paneId) {
                        guard let ghosttyApp else { continue }
                        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, fd: result.fd)
                        let pid = result.pid
                        await MainActor.run {
                            guard paneRenderers[paneId] == nil else { return }
                            renderer.configureForReconnect(paneId: paneId, pid: pid)
                            paneRenderers[paneId] = renderer
                            renderer.nsView.onFocusGained = { [weak self] in
                                self?.lastFocusedPaneId = paneId
                            }
                            renderer.onOutput = { [weak self] data in
                                self?.paneActivityWatcher?.processOutput(paneId: paneId, data: data)
                            }
                            ForgeLog.log("[daemon] Reconnected pane \(paneId) (fd=\(result.fd), pid=\(pid))")
                        }
                    } else {
                        await MainActor.run {
                            guard paneRenderers[paneId] == nil else { return }
                            guard let pane = tab.panes.first(where: { $0.id == paneId }) else { return }
                            let renderer = createExecRenderer(for: pane, cwd: cwd)
                            paneRenderers[paneId] = renderer
                            if let ghostty = renderer as? GhosttyRenderer {
                                ghostty.startScrollbackLog(paneId: paneId)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    let fd = ghostty.ptyFD
                                    if fd >= 0 {
                                        let pid = ghostty.foregroundPID
                                        Task {
                                            try? await daemon.store(paneId: paneId, fd: fd, pid: pid, cwd: cwd)
                                            ForgeLog.log("[daemon] Stored fd=\(fd) for pane \(paneId)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else if !panesToCreate.isEmpty {
            for (pane, cwd) in panesToCreate {
                let renderer = createExecRenderer(for: pane, cwd: cwd)
                paneRenderers[pane.id] = renderer
            }
        }

        if let lfp = lastFocusedPaneId, !activePaneIds.contains(lfp) {
            lastFocusedPaneId = tab.panes.first?.id
        }
        let focusId = lastFocusedPaneId ?? tab.panes.last?.id
        for (id, renderer) in paneRenderers {
            renderer.setFocused(id == focusId)
        }

        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
    }
}
