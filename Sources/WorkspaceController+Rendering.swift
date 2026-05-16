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

            // Set control mode client size so the tmux window is large enough
            // for all panes. Derive total cols/rows from the terminal area frame
            // and the cell size (computed from this renderer's grid vs pixel dims).
            let viewFrame = renderer.view.frame
            if cols > 0, rows > 0, viewFrame.width > 0, viewFrame.height > 0 {
                let cellW = viewFrame.width / CGFloat(cols)
                let cellH = viewFrame.height / CGFloat(rows)
                let areaSize = self.terminalAreaSize
                let refWidth = areaSize.width > 0 ? areaSize.width : viewFrame.width
                let refHeight = areaSize.height > 0 ? areaSize.height : viewFrame.height
                let totalCols = max(Int(refWidth / cellW), cols)
                let totalRows = max(Int(refHeight / cellH), rows)
                adapter.controlModeSend("refresh-client -C \(totalCols),\(totalRows)")
            }

            adapter.controlModeSend("resize-pane -t \(paneId) -x \(cols) -y \(rows)")
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
