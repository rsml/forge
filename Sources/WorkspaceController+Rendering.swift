import AppKit
import SwiftTerm
import ForgeCore

/// Native pane rendering: renderer creation, lifecycle, and scrollback seeding.
extension WorkspaceController {

    /// Creates a renderer for the given pane, wires input/resize callbacks,
    /// and registers it with the output router.
    /// Uses GhosttyRenderer when ghosttyApp is available, falls back to SwiftTermRenderer.
    func createRenderer(for pane: Pane) -> any TerminalRenderer {
        let paneId = pane.id
        let renderer: any TerminalRenderer

        if let ghosttyApp {
            let ghosttyRenderer = GhosttyRenderer(ghosttyApp: ghosttyApp)
            // Click-to-focus: tell tmux which pane is active when the user clicks.
            ghosttyRenderer.nsView.onFocusGained = { [weak self] in
                guard let self, let adapter = self.tmux as? TmuxAdapter else { return }
                adapter.controlModeSend("select-pane -t \(paneId)")
            }
            renderer = ghosttyRenderer
        } else {
            let font = resolvedTerminalFont
            let (foreground, background, palette) = resolvedTerminalColors
            renderer = SwiftTermRenderer(
                font: font,
                foreground: foreground,
                background: background,
                colors: palette
            )
        }

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
            if let text = String(data: data, encoding: .utf8) {
                // Escape semicolons and other tmux-special chars in literal mode
                let escaped = text.replacingOccurrences(of: ";", with: "\\;")
                adapter.controlModeSend("send-keys -l -t \(paneId) \(escaped)")
            }
        }

        // Wire resize to tmux — fires when the renderer calculates cols/rows from frame.
        // Two-step: first set the control mode client size (so the tmux window is large
        // enough), then resize the individual pane within that window.
        renderer.onResize = { [weak self] cols, rows in
            guard let self, let adapter = self.tmux as? TmuxAdapter else { return }
            ForgeLog.log("[debug] Renderer \(paneId) resize: \(cols)x\(rows)")

            // Compute cell size (once) — used by PaneSplitView dividers so
            // SwiftUI's pixel layout matches tmux's cell-based layout exactly.
            let viewFrame = renderer.view.frame
            if self.terminalCellSize == .zero, cols > 0, rows > 0,
               viewFrame.width > 0, viewFrame.height > 0 {
                self.terminalCellSize = CGSize(
                    width: viewFrame.width / CGFloat(cols),
                    height: viewFrame.height / CGFloat(rows)
                )
            }

            // Store every pane's latest size and schedule a batched flush.
            self.pendingResizes[paneId] = (cols, rows)
            self.scheduleResizeFlush()
        }

        outputRouter.register(paneId: paneId, renderer: renderer)
        return renderer
    }

    /// Synchronizes renderers with the active tab's panes.
    /// Creates renderers for new panes, removes stale ones.
    func updateRenderers() {
        guard config.isNativePaneRendering else { return }

        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else {
            paneRenderers.removeAll()
            outputRouter.unregisterAll()
            return
        }

        let livePaneIds = Set(tab.panes.map(\.id))

        // Remove stale renderers (panes that no longer exist)
        for id in paneRenderers.keys where !livePaneIds.contains(id) {
            paneRenderers.removeValue(forKey: id)
            outputRouter.unregister(paneId: id)
        }

        // Create renderers for new panes
        for pane in tab.panes where paneRenderers[pane.id] == nil {
            let renderer = createRenderer(for: pane)
            paneRenderers[pane.id] = renderer
        }

        // Update cursor focus: only the active pane gets a blinking cursor,
        // others show an outline (unfocused) cursor.
        let activePaneId = tab.panes.first(where: \.active)?.id
        for (id, renderer) in paneRenderers {
            renderer.setFocused(id == activePaneId)
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

        // Compute total window size from any pane's cell metrics
        if let (firstId, firstSize) = pendingResizes.first,
           let renderer = paneRenderers[firstId] {
            let frame = renderer.view.frame
            if firstSize.cols > 0, firstSize.rows > 0, frame.width > 0, frame.height > 0 {
                let cellW = frame.width / CGFloat(firstSize.cols)
                let cellH = frame.height / CGFloat(firstSize.rows)
                let ref = terminalAreaSize.width > 0 ? terminalAreaSize : frame.size
                let totalCols = max(Int(ref.width / cellW), firstSize.cols)
                let totalRows = max(Int(ref.height / cellH), firstSize.rows)
                adapter.controlModeSend("refresh-client -C \(totalCols),\(totalRows)")
                // Toggle window size to force tmux to redraw all panes.
                // If the window is already the target size, resize-window is a
                // no-op and tmux won't send %output. The +1/-1 toggle guarantees
                // a real resize → tmux redraws → %output populates all surfaces.
                adapter.controlModeSend("resize-window -t \(firstId) -x \(totalCols + 1) -y \(totalRows)")
                adapter.controlModeSend("resize-window -t \(firstId) -x \(totalCols) -y \(totalRows)")
            }
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

    // MARK: - Private Helpers

    private var resolvedTerminalFont: NSFont {
        let family = config.config.terminalFont?.family ??
                     config.config.terminal?.fontFamily ??
                     config.config.appearance?.fontFamily
        let size = config.config.terminalFont?.size ??
                   config.config.terminal?.fontSize ??
                   config.config.appearance?.fontSize ?? 13
        return FontResolver.resolveTerminalFont(family: family, size: CGFloat(size))
    }

    private var resolvedTerminalColors: (foreground: NSColor, background: NSColor, palette: [SwiftTerm.Color]?) {
        if let theme = config.resolvedTheme {
            let fg = NSColor(theme.foreground.color)
            let bg = NSColor(theme.background.color)
            let palette = theme.ansiColors.prefix(16).map { ForgeTerminalView.themeColorToTermColor($0) }
            return (fg, bg, palette.count == 16 ? palette : nil)
        }
        let fg = NSColor(red: 0.77, green: 0.78, blue: 0.78, alpha: 1.0)
        let bg = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
        return (fg, bg, nil)
    }
}
