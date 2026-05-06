import Foundation
import ForgeCore

/// Concrete implementation of TmuxQueryPort, TmuxCommandPort, and TmuxControlPort
/// using the tmux CLI + control mode.
@MainActor
final class TmuxAdapter: TmuxQueryPort, TmuxCommandPort, TmuxControlPort {
    private let runner = TmuxCommandRunner()
    var configPath: String? { runner.configPath }
    private lazy var controlMode = TmuxControlMode(
        tmuxPath: runner.tmuxPath,
        socketName: runner.socketName,
        configPath: runner.configPath
    )

    func listProjects() async -> [ProjectInfo] {
        guard let output = await runner.run("list-sessions", "-F", TmuxStateParser.projectFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parseProjects(output)
    }

    func listTabs(project: String) async -> [TabInfo] {
        guard let output = await runner.run("list-windows", "-t", project, "-F", TmuxStateParser.tabFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parseTabs(output)
    }

    func listAllTabs() async -> [TabInfo] {
        guard let output = await runner.run("list-windows", "-a", "-F", TmuxStateParser.tabFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parseTabs(output)
    }

    func listPanes(tab: String) async -> [PaneInfo] {
        guard let output = await runner.run("list-panes", "-t", tab, "-F", TmuxStateParser.paneFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parsePanes(output)
    }

    func listAllPanes() async -> [PaneInfo] {
        guard let output = await runner.run("list-panes", "-a", "-F", TmuxStateParser.paneFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parsePanes(output)
    }

    func newProject(name: String, path: String) async -> Bool {
        await runner.run("new-session", "-d", "-s", name, "-c", path) != nil
    }

    func killProject(name: String) async {
        controlMode.send("kill-session -t \(shellQuote(name))")
    }

    func renameProject(target: String, newName: String) async {
        controlMode.send("rename-session -t \(shellQuote(target)) \(shellQuote(newName))")
    }

    func newTab(project: String, path: String?) async {
        var cmd = "new-window -t \(shellQuote("\(project):"))"
        if let path { cmd += " -c \(shellQuote(path))" }
        controlMode.send(cmd)
    }

    func killTab(id: String) async {
        controlMode.send("kill-window -t \(id)")
    }

    func selectTab(id: String) async {
        controlMode.send("select-window -t \(id)")
    }

    func renameTab(id: String, newName: String) async {
        controlMode.send("rename-window -t \(id) \(shellQuote(newName))")
    }

    func killPane(id: String) async {
        controlMode.send("kill-pane -t \(id)")
    }

    func selectPane(id: String) async {
        controlMode.send("select-pane -t \(id)")
    }

    func switchClient(project: String) async {
        controlMode.send("switch-client -t \(shellQuote(project))")
    }

    func splitWindow(id: String, direction: SplitDirection) async {
        let flag = direction == .horizontal ? "-h" : "-v"
        controlMode.send("split-window \(flag) -t \(id)")
    }

    func swapTab(id: String, offset: Int) async {
        let target = offset > 0 ? "+\(offset)" : "\(offset)"
        controlMode.send("swap-window -s \(id) -t \(target)")
    }

    func reorderTab(id: String, swapWith: [String]) async {
        for targetId in swapWith {
            controlMode.send("swap-window -s \(id) -t \(targetId)")
        }
    }

    func moveTab(id: String, toSession: String) async {
        controlMode.send("move-window -s \(id) -t \(shellQuote("\(toSession):"))")
    }

    func sourceConfig(path: String) async {
        _ = await runner.run("source-file", path)
    }

    func clearHistory(pane: String) async {
        controlMode.send("clear-history -t \(pane)")
        controlMode.send("send-keys -t \(pane) C-l")
    }

    func capturePaneContent(id: String, lastN: Int) async -> String? {
        await runner.run("capture-pane", "-p", "-t", id, "-S", "-\(lastN)")
    }

    func startControlMode(
        onEvent: @escaping @Sendable (String) -> Void,
        onDisconnect: (@Sendable () -> Void)?,
        onReconnect: (@Sendable () -> Void)?
    ) {
        controlMode.start(onEvent: onEvent, onDisconnect: onDisconnect, onReconnect: onReconnect)
    }

    func stopControlMode() {
        controlMode.stop()
    }

    // Wraps s in single quotes and escapes any embedded single quotes so the
    // resulting token is safe to embed in a tmux control-mode command string.
    // Example: "my 'proj'" → "'my '\\''proj'\\'''"
    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
