import SwiftUI
import SwiftTerm
import AppKit

/// Wraps SwiftTerm's LocalProcessTerminalView to display a tmux session.
/// This is a stopgap — will be replaced with libghostty rendering.
struct ForgeTerminalView: NSViewRepresentable {
    let sessionName: String
    let tmux: TmuxController

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        // Configure appearance to match Ghostty/Seti dark theme
        terminal.nativeForegroundColor = NSColor(red: 0.77, green: 0.78, blue: 0.78, alpha: 1.0) // #c5c8c6
        terminal.nativeBackgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0) // #1a1a1a

        // Set font
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Start tmux attach process
        let tmuxPath = findTmux()
        terminal.startProcess(
            executable: tmuxPath,
            args: [tmuxPath, "attach-session", "-t", sessionName],
            environment: buildEnvironment(),
            execName: "tmux"
        )

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // SwiftTerm handles updates internally
    }

    private func findTmux() -> String {
        for path in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"] {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "/opt/homebrew/bin/tmux"
    }

    private func buildEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env.map { "\($0.key)=\($0.value)" }
    }
}
