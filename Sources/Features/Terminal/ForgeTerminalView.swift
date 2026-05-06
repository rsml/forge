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

        let configFontFamily = configStore.config.terminalFont?.family ??
                               configStore.config.terminal?.fontFamily ??
                               configStore.config.appearance?.fontFamily
        let configFontSize = configStore.config.terminalFont?.size ??
                             configStore.config.terminal?.fontSize ??
                             configStore.config.appearance?.fontSize ?? 13
        terminal.font = resolveTerminalFont(family: configFontFamily, size: CGFloat(configFontSize))

        // Apply theme colors
        if let theme = resolveTheme() {
            terminal.nativeForegroundColor = NSColor(theme.foreground)
            terminal.nativeBackgroundColor = NSColor(theme.background)
            let palette = theme.ansiColors.prefix(16).map { Self.swiftUIColorToTermColor($0) }
            if palette.count == 16 {
                terminal.installColors(palette)
            }
        } else {
            terminal.nativeForegroundColor = NSColor(red: 0.77, green: 0.78, blue: 0.78, alpha: 1.0)
            terminal.nativeBackgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
        }

        let tmuxPath = findTmux()
        let configArg: String
        if let configPath = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("forge-tmux.conf").path,
            FileManager.default.fileExists(atPath: configPath) {
            configArg = "-f \(configPath) "
        } else {
            configArg = ""
        }
        let socketArg = "-L forge"

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
        let configFontFamily = configStore.config.terminalFont?.family ??
                               configStore.config.terminal?.fontFamily ??
                               configStore.config.appearance?.fontFamily
        let configFontSize = configStore.config.terminalFont?.size ??
                             configStore.config.terminal?.fontSize ??
                             configStore.config.appearance?.fontSize ?? 13
        let newFont = resolveTerminalFont(family: configFontFamily, size: CGFloat(configFontSize))
        if nsView.font != newFont {
            nsView.font = newFont
        }

        // Reactive theme update
        if let theme = resolveTheme() {
            let newFg = NSColor(theme.foreground)
            let newBg = NSColor(theme.background)
            if nsView.nativeForegroundColor != newFg { nsView.nativeForegroundColor = newFg }
            if nsView.nativeBackgroundColor != newBg { nsView.nativeBackgroundColor = newBg }
        }
    }

    /// Looks up the selected theme from config and parses it.
    private func resolveTheme() -> ThemeDefinition? {
        guard let themeId = configStore.config.theme?.source else { return nil }
        let searchPaths = [
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
            (NSHomeDirectory() as NSString).appendingPathComponent(".config/ghostty/themes"),
        ]
        for searchPath in searchPaths {
            let path = (searchPath as NSString).appendingPathComponent(themeId)
            if let theme = ThemeParser.parseThemeFile(path: path, id: themeId) {
                return theme
            }
        }
        return nil
    }

    /// Converts a SwiftUI Color to SwiftTerm's Color (UInt16 components, 0-65535).
    private static func swiftUIColorToTermColor(_ color: SwiftUI.Color) -> SwiftTerm.Color {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SwiftTerm.Color(red: UInt16(r * 65535), green: UInt16(g * 65535), blue: UInt16(b * 65535))
    }

    /// Resolves the best available monospaced font with Nerd Font glyph coverage.
    ///
    /// Priority:
    /// 1. Font declared in ~/.config/ghostty/config (`font-family = ...`)
    /// 2. Common Nerd Font families installed on the system
    /// 3. System monospaced font (final fallback, no Nerd Font glyphs)
    private func resolveTerminalFont(family: String? = nil, size: CGFloat) -> NSFont {
        if let family, let font = NSFont(name: family, size: size) {
            return font
        }
        let fallbacks = [
            "Dank Mono",
            "MesloLGS NF",
            "MesloLGM Nerd Font",
            "JetBrainsMono Nerd Font",
            "JetBrains Mono NL",
            "FiraCode Nerd Font",
            "Hack Nerd Font",
            "SauceCodePro Nerd Font",
            "DejaVuSansMono Nerd Font",
        ]
        let candidates = (ghosttyFontFamily().map { [$0] } ?? []) + fallbacks

        for family in candidates {
            if let font = NSFont(name: family, size: size) {
                return font
            }
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Parses `font-family = <name>` from the Ghostty config file, if present.
    private func ghosttyFontFamily() -> String? {
        let configPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/ghostty/config")
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("font-family"), trimmed.contains("=") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func findTmux() -> String {
        if let bundledPath = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("tmux").path,
            FileManager.default.fileExists(atPath: bundledPath) {
            return bundledPath
        }
        return ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
            .first { FileManager.default.fileExists(atPath: $0) }
            ?? "/opt/homebrew/bin/tmux"
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env.map { "\($0.key)=\($0.value)" }
    }
}
