import SwiftUI
import SwiftTerm
import AppKit

/// SwiftTerm wrapper — stopgap until libghostty integration.
struct ForgeTerminalView: NSViewRepresentable {
    @Environment(ForgeConfigStore.self) private var configStore
    let sessionName: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.autoresizingMask = [.width, .height]

        // Hide the legacy scroller — tmux manages scrollback
        for subview in terminal.subviews {
            if let scroller = subview as? NSScroller {
                scroller.isHidden = true
            }
        }

        terminal.font = resolvedFont

        // Apply theme colors
        if let theme = configStore.resolvedTheme {
            terminal.nativeForegroundColor = NSColor(theme.foreground.color)
            terminal.nativeBackgroundColor = NSColor(theme.background.color)
            let palette = theme.ansiColors.prefix(16).map { Self.themeColorToTermColor($0) }
            if palette.count == 16 {
                terminal.installColors(palette)
            }
        } else {
            terminal.nativeForegroundColor = NSColor(red: 0.77, green: 0.78, blue: 0.78, alpha: 1.0)
            terminal.nativeBackgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
        }

        let runner = TmuxCommandRunner()
        let tmuxPath = runner.tmuxPath
        let configArg = runner.configPath.map { "-f \($0) " } ?? ""
        let socketArg = "-L \(runner.socketName)"

        // Hide tmux status bar — Forge provides the tab UI
        let shell = "/bin/zsh"
        let cmd = "\(tmuxPath) \(socketArg) \(configArg)set-option -g fill-character ' ' 2>/dev/null; \(tmuxPath) \(socketArg) \(configArg)set-option -g mouse off 2>/dev/null; \(tmuxPath) \(socketArg) \(configArg)set-option -g status off 2>/dev/null; \(tmuxPath) \(socketArg) \(configArg)attach-session -t \(sessionName)"
        terminal.startProcess(
            executable: shell,
            args: ["-c", cmd],
            environment: buildEnvironment(),
            execName: "zsh"
        )

        // Grab focus so the terminal receives keyboard input
        DispatchQueue.main.async {
            terminal.window?.makeFirstResponder(terminal)
        }

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Scrollers may not exist during makeNSView; hide them here where the
        // view hierarchy is guaranteed to be fully assembled.
        for subview in nsView.subviews {
            if let scroller = subview as? NSScroller {
                scroller.isHidden = true
            }
        }

        // Reactive font update
        let newFont = resolvedFont
        if nsView.font != newFont {
            nsView.font = newFont
        }

        // Reactive theme update
        if let theme = configStore.resolvedTheme {
            let newFg = NSColor(theme.foreground.color)
            let newBg = NSColor(theme.background.color)
            if nsView.nativeForegroundColor != newFg { nsView.nativeForegroundColor = newFg }
            if nsView.nativeBackgroundColor != newBg { nsView.nativeBackgroundColor = newBg }
        }
    }

    // MARK: - Private

    private var resolvedFont: NSFont {
        let family = configStore.config.terminalFont?.family ??
                     configStore.config.terminal?.fontFamily ??
                     configStore.config.appearance?.fontFamily
        let size = configStore.config.terminalFont?.size ??
                   configStore.config.terminal?.fontSize ??
                   configStore.config.appearance?.fontSize ?? 13
        return FontResolver.resolveTerminalFont(family: family, size: CGFloat(size))
    }

    /// Converts a ThemeColor to SwiftTerm's Color (UInt16 components, 0-65535).
    private static func themeColorToTermColor(_ color: ThemeColor) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16(color.red * 65535),
            green: UInt16(color.green * 65535),
            blue: UInt16(color.blue * 65535)
        )
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env.map { "\($0.key)=\($0.value)" }
    }
}
