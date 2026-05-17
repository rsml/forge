import AppKit
import ForgeCore

/// Native pane rendering: renderer creation, lifecycle, and scrollback seeding.
extension WorkspaceController {

    /// Creates a renderer for the given pane, wires input/resize callbacks,
    /// and registers it with the output router.
    func createRenderer(for pane: Pane) -> any TerminalRenderer {
        let paneId = pane.id

        guard let ghosttyApp else { fatalError("createRenderer requires ghosttyApp") }
        let ghosttyRenderer = GhosttyRenderer(ghosttyApp: ghosttyApp)
        // Click-to-focus: tell tmux which pane is active when the user clicks.
        ghosttyRenderer.nsView.onFocusGained = { [weak self] in
            guard let self, let adapter = self.tmux as? TmuxAdapter else { return }
            adapter.controlModeSend("select-pane -t \(paneId)")
        }
        let renderer: any TerminalRenderer = ghosttyRenderer

        // Wire keyboard input to tmux via control mode (sub-ms latency).
        // Use send-keys -l (literal) for printable text — it goes through the
        // PTY line discipline properly. For control bytes and escape sequences,
        // use send-keys with tmux key names or -H for raw bytes.
        renderer.onInput = { [weak self] data in
            guard let self, let adapter = self.tmux as? TmuxAdapter else { return }

            // Single control byte (0x00-0x1F) → use tmux key names for proper PTY handling
            if data.count == 1, let byte = data.first, byte <= 0x1F {
                let keyName: String? = switch byte {
                case 0x00: "C-Space"
                case 0x01...0x1A: "C-\(Character(UnicodeScalar(byte + 0x60)))"
                case 0x1B: "Escape"
                case 0x1C: "C-\\"
                case 0x1D: "C-]"
                case 0x1E: "C-^"
                case 0x1F: "C-_"
                default: nil
                }
                if let keyName {
                    adapter.controlModeSend("send-keys -t \(paneId) \(keyName)")
                    return
                }
            }

            // DEL (backspace on most terminals)
            if data.count == 1, data.first == 0x7F {
                adapter.controlModeSend("send-keys -t \(paneId) BSpace")
                return
            }

            // Escape sequences (starts with 0x1B and has more bytes) → send-keys -H
            if data.count > 1, data.first == 0x1B {
                let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                adapter.controlModeSend("send-keys -H -t \(paneId) \(hex)")
                return
            }

            // Printable text → send-keys -l (literal, proper PTY handling)
            // Must be quoted — bare spaces/special chars are stripped by tmux's parser.
            if let text = String(data: data, encoding: .utf8) {
                var escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
                escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
                escaped = escaped.replacingOccurrences(of: ";", with: "\\;")
                adapter.controlModeSend("send-keys -l -t \(paneId) \"\(escaped)\"")
            }
        }

        // Wire resize to tmux — fires when the renderer calculates cols/rows from frame.
        // Two-step: first set the control mode client size (so the tmux window is large
        // enough), then resize the individual pane within that window.
        renderer.onResize = { [weak self] cols, rows in
            guard let self, let adapter = self.tmux as? TmuxAdapter else { return }
            ForgeLog.log("[debug] Renderer \(paneId) resize: \(cols)x\(rows)")

            // Get exact cell size from ghostty's font metrics (once).
            // This is authoritative — not derived from frame/cols math,
            // which varies per pane due to integer truncation.
            if self.terminalCellSize == .zero,
               let ghostty = renderer as? GhosttyRenderer {
                let exact = ghostty.exactCellSize
                if exact.width > 0, exact.height > 0 {
                    self.terminalCellSize = exact
                    ForgeLog.log("[debug] Cell size from ghostty: \(exact.width)x\(exact.height)")
                }
            }

            // Store every pane's latest size and schedule a batched flush.
            self.pendingResizes[paneId] = (cols, rows)
            self.scheduleResizeFlush()
        }

        outputRouter.register(paneId: paneId, renderer: renderer)
        return renderer
    }

    /// Creates an EXEC mode renderer — Ghostty owns the PTY directly.
    func createExecRenderer(for pane: Pane, cwd: String) -> any TerminalRenderer {
        guard let ghosttyApp else { fatalError("nativePTY requires ghosttyApp") }
        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, cwd: cwd)
        // Track which pane was last focused (for split targeting)
        let paneId = pane.id
        renderer.nsView.onFocusGained = { [weak self] in
            self?.lastFocusedPaneId = paneId
        }
        return renderer
    }

    /// Synchronizes renderers with the active tab's panes.
    /// Dispatches to the appropriate path based on feature flags.
    func updateRenderers() {
        guard config.isNativePaneRendering || config.isNativePTY else { return }

        if config.isNativePTY {
            updateRenderersNativePTY()
        } else {
            updateRenderersLegacy()
        }
    }

    /// Legacy renderer path: tmux control mode IO (MANUAL mode).
    private func updateRenderersLegacy() {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else {
            paneRenderers.removeAll()
            outputRouter.unregisterAll()
            return
        }

        let livePaneIds = Set(tab.panes.map(\.id))

        for id in paneRenderers.keys where !livePaneIds.contains(id) {
            paneRenderers.removeValue(forKey: id)
            outputRouter.unregister(paneId: id)
        }

        for pane in tab.panes where paneRenderers[pane.id] == nil {
            let renderer = createRenderer(for: pane)
            paneRenderers[pane.id] = renderer
        }

        let activePaneId = tab.panes.first(where: \.active)?.id
        for (id, renderer) in paneRenderers {
            renderer.setFocused(id == activePaneId)
        }
    }

    /// Native PTY renderer path: EXEC mode (Ghostty owns PTY directly).
    private func updateRenderersNativePTY() {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else {
            paneRenderers.removeAll()
            return
        }

        let livePaneIds = Set(tab.panes.map(\.id))

        for id in paneRenderers.keys where !livePaneIds.contains(id) {
            paneRenderers.removeValue(forKey: id)
        }

        for pane in tab.panes where paneRenderers[pane.id] == nil {
            let cwd = pane.currentPath.isEmpty ? (project.path ?? NSHomeDirectory()) : pane.currentPath

            // Try to reconnect to an existing PTY from the daemon first.
            // If the daemon has a stored fd for this pane, create an EXTERNAL_FD
            // renderer (reconnect). Otherwise, create a fresh EXEC renderer.
            if let daemon = daemonAdapter {
                let paneId = pane.id
                Task {
                    if let result = try? await daemon.retrieve(paneId: paneId) {
                        // Reconnect to existing PTY
                        guard let ghosttyApp else { return }
                        let renderer = GhosttyRenderer(ghosttyApp: ghosttyApp, fd: result.fd)
                        await MainActor.run {
                            paneRenderers[paneId] = renderer
                            ForgeLog.log("[daemon] Reconnected pane \(paneId) (fd=\(result.fd), pid=\(result.pid))")
                            // Trigger shell redraw after surface is connected and sized.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                let fd = result.fd
                                let frame = renderer.view.frame
                                guard frame.width > 0, frame.height > 0 else {
                                    ForgeLog.log("[daemon] Skipping TIOCSWINSZ — frame is zero")
                                    return
                                }
                                // Use exact cell size from ghostty, or estimate from font
                                let cellSize = renderer.exactCellSize
                                let cw = cellSize.width > 0 ? cellSize.width : 9.0
                                let ch = cellSize.height > 0 ? cellSize.height : 19.0
                                var ws = winsize()
                                ws.ws_col = UInt16(frame.width / cw)
                                ws.ws_row = UInt16(frame.height / ch)
                                ws.ws_xpixel = UInt16(frame.width)
                                ws.ws_ypixel = UInt16(frame.height)
                                _ = ioctl(fd, TIOCSWINSZ, &ws)
                                ForgeLog.log("[daemon] TIOCSWINSZ fd=\(fd) → \(ws.ws_col)x\(ws.ws_row)")
                                if result.pid > 0 {
                                    kill(result.pid, SIGWINCH)
                                }
                            }
                        }
                        return
                    }
                    // No stored fd — create fresh EXEC surface
                    await MainActor.run {
                        let renderer = createExecRenderer(for: pane, cwd: cwd)
                        paneRenderers[paneId] = renderer
                        // Send fd to daemon after forkpty completes
                        if let ghostty = renderer as? GhosttyRenderer {
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
            } else {
                // No daemon — just create EXEC renderer
                let renderer = createExecRenderer(for: pane, cwd: cwd)
                paneRenderers[pane.id] = renderer
            }
        }

        // Use lastFocusedPaneId for cursor focus (\.active is tmux-only)
        let focusId = lastFocusedPaneId ?? tab.panes.last?.id
        for (id, renderer) in paneRenderers {
            renderer.setFocused(id == focusId)
        }

        // Save workspace structure after any renderer change (continuous persistence)
        if config.isNativePTY {
            let frame = NSApp.mainWindow?.frame
            WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
        }
    }

    /// Schedule a batched resize flush after all renderers have reported sizes.
    /// During drag, the flush is deferred until drag ends.
    func scheduleResizeFlush() {
        if suppressPaneResize { return }
        resizeFlushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.flushPendingResizes()
        }
        resizeFlushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// Send all stored resize commands as a single batch.
    /// resize-window first (sets total), then resize-pane for each pane.
    func flushPendingResizes() {
        guard !pendingResizes.isEmpty, let adapter = tmux as? TmuxAdapter else { return }
        ForgeLog.log("[debug] Flushing \(pendingResizes.count) pending resizes (cellSize=\(terminalCellSize))")

        // Compute total window size. Prefer the exact ghostty cell size;
        // fall back to deriving from any pane's frame/cols if not yet available.
        var cellW = terminalCellSize.width
        var cellH = terminalCellSize.height
        if cellW <= 0 || cellH <= 0, let (firstId, firstSize) = pendingResizes.first,
           let renderer = paneRenderers[firstId] {
            let frame = renderer.view.frame
            if firstSize.cols > 0, firstSize.rows > 0, frame.width > 0, frame.height > 0 {
                cellW = frame.width / CGFloat(firstSize.cols)
                cellH = frame.height / CGFloat(firstSize.rows)
            }
        }
        let area = terminalAreaSize
        if let firstId = pendingResizes.keys.first,
           cellW > 0, cellH > 0, area.width > 0, area.height > 0 {
            let totalCols = Int(area.width / cellW)
            let totalRows = Int(area.height / cellH)
            adapter.controlModeSend("refresh-client -C \(totalCols)x\(totalRows)")
            // Toggle window size to force tmux to redraw all panes.
            // If the window is already the target size, resize-window is a
            // no-op and tmux won't send %output. The +1/-1 toggle guarantees
            // a real resize → tmux redraws → %output populates all surfaces.
            adapter.controlModeSend("resize-window -t \(firstId) -x \(totalCols + 1) -y \(totalRows)")
            adapter.controlModeSend("resize-window -t \(firstId) -x \(totalCols) -y \(totalRows)")
        }

        // Only send resize-pane after drag (user explicitly set proportions).
        // On startup, divider width matches tmux's cell dimensions, so
        // resize-window alone produces matching cell counts — no resize-pane
        // needed, and proportions are preserved.
        if sendResizePaneOnFlush {
            for (paneId, size) in pendingResizes {
                adapter.controlModeSend("resize-pane -t \(paneId) -x \(size.cols) -y \(size.rows)")
            }
            sendResizePaneOnFlush = false
        }
        pendingResizes.removeAll()
    }

}
