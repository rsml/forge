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

    func listSessions() async -> [SessionInfo] {
        guard let output = await runner.run("list-sessions", "-F", TmuxStateParser.sessionFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parseSessions(output)
    }

    func listWindows(session: String) async -> [WindowInfo] {
        guard let output = await runner.run("list-windows", "-t", session, "-F", TmuxStateParser.windowFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parseWindows(output)
    }

    func listAllWindows() async -> [WindowInfo] {
        guard let output = await runner.run("list-windows", "-a", "-F", TmuxStateParser.windowFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parseWindows(output)
    }

    func listPanes(window: String) async -> [PaneInfo] {
        guard let output = await runner.run("list-panes", "-t", window, "-F", TmuxStateParser.paneFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parsePanes(output)
    }

    func listAllPanes() async -> [PaneInfo] {
        guard let output = await runner.run("list-panes", "-a", "-F", TmuxStateParser.paneFormat),
              !output.isEmpty else { return [] }
        return TmuxStateParser.parsePanes(output)
    }

    func newSession(name: String, path: String) async {
        _ = await runner.run("new-session", "-d", "-s", name, "-c", path)
    }

    func killSession(name: String) async {
        controlMode.send("kill-session -t \(name)")
    }

    func renameSession(target: String, newName: String) async {
        controlMode.send("rename-session -t \(target) \(newName)")
    }

    func newWindow(session: String, path: String?) async {
        var cmd = "new-window -t '\(session):'"
        if let path { cmd += " -c '\(path)'" }
        controlMode.send(cmd)
    }

    func killWindow(id: String) async {
        controlMode.send("kill-window -t \(id)")
    }

    func selectWindow(id: String) async {
        controlMode.send("select-window -t \(id)")
    }

    func renameWindow(id: String, newName: String) async {
        controlMode.send("rename-window -t \(id) \(newName)")
    }

    func killPane(id: String) async {
        controlMode.send("kill-pane -t \(id)")
    }

    func selectPane(id: String) async {
        controlMode.send("select-pane -t \(id)")
    }

    func switchClient(session: String) async {
        controlMode.send("switch-client -t \(session)")
    }

    func splitWindow(id: String, direction: SplitDirection) async {
        let flag = direction == .horizontal ? "-h" : "-v"
        controlMode.send("split-window \(flag) -t \(id)")
    }

    func swapWindow(id: String, offset: Int) async {
        let target = offset > 0 ? "+\(offset)" : "\(offset)"
        controlMode.send("swap-window -s \(id) -t \(target)")
    }

    func reorderWindow(id: String, swapWith: [String]) async {
        for targetId in swapWith {
            controlMode.send("swap-window -s \(id) -t \(targetId)")
        }
    }

    func moveWindow(id: String, toSession: String) async {
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
