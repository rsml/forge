import Foundation
import ForgeDomain

/// Concrete implementation of TmuxPort using the tmux CLI + control mode
@MainActor
final class TmuxAdapter: TmuxPort {
    private let runner = TmuxCommandRunner()
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

    func newProject(name: String, path: String) async {
        _ = await runner.run("new-session", "-d", "-s", name, "-c", path)
    }

    func killProject(name: String) async {
        controlMode.send("kill-session -t \(name)")
    }

    func renameProject(target: String, newName: String) async {
        controlMode.send("rename-session -t \(target) \(newName)")
    }

    func newTab(project: String, path: String?) async {
        var cmd = "new-window -t '\(project):'"
        if let path { cmd += " -c '\(path)'" }
        controlMode.send(cmd)
    }

    func killTab(id: String) async {
        controlMode.send("kill-window -t \(id)")
    }

    func selectTab(id: String) async {
        controlMode.send("select-window -t \(id)")
    }

    func renameTab(id: String, newName: String) async {
        controlMode.send("rename-window -t \(id) \(newName)")
    }

    func killPane(id: String) async {
        controlMode.send("kill-pane -t \(id)")
    }

    func selectPane(id: String) async {
        controlMode.send("select-pane -t \(id)")
    }

    func switchClient(project: String) async {
        controlMode.send("switch-client -t \(project)")
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
        controlMode.send("move-window -s \(id) -t '\(toSession):'")
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

    func startControlMode(onEvent: @escaping @Sendable (String) -> Void) {
        controlMode.start(onEvent: onEvent)
    }

    func stopControlMode() {
        controlMode.stop()
    }
}
