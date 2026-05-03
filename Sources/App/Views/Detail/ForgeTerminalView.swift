import SwiftUI
import SwiftTerm
import AppKit

/// SwiftTerm wrapper — stopgap until libghostty integration.
struct ForgeTerminalView: NSViewRepresentable {
    let sessionName: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)

        terminal.nativeForegroundColor = NSColor(red: 0.77, green: 0.78, blue: 0.78, alpha: 1.0)
        terminal.nativeBackgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
        terminal.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        let tmuxPath = findTmux()

        // Hide tmux status bar — Forge provides the tab UI
        let shell = "/bin/zsh"
        let cmd = "\(tmuxPath) set-option -g status off 2>/dev/null; \(tmuxPath) attach-session -t \(sessionName)"
        terminal.startProcess(
            executable: shell,
            args: ["-c", cmd],
            environment: buildEnvironment(),
            execName: "zsh"
        )

        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    private func findTmux() -> String {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
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
