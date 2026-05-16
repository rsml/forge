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

    /// Set before starting control mode to skip `refresh-client -C 1x1` for native rendering.
    var nativeRendering: Bool {
        get { controlMode.nativeRendering }
        set { controlMode.nativeRendering = newValue }
    }

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

    func newTab(project: String, path: String?) async -> String? {
        var args = ["new-window", "-P", "-F", "#{window_id}", "-t", "\(project):"]
        if let path { args += ["-c", path] }
        return await runner.run(args)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func killTab(id: String) async {
        _ = await runner.run("kill-window", "-t", id)
    }

    func selectTab(id: String) async {
        controlMode.send("select-window -t \(id)")
        // Force the window to match the current client dimensions immediately.
        // Without this, inactive windows retain their old size and show a
        // fill-character bar on the right edge until tmux catches up.
        controlMode.send("resize-window -A -t \(id)")
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
        controlMode.send("swap-window -d -s \(id) -t \(target)")
    }

    func reorderTab(id: String, swapWith: [String]) async {
        for targetId in swapWith {
            controlMode.send("swap-window -d -s \(id) -t \(targetId)")
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

    func clearBellFlag(tabId: String) async {
        _ = await runner.run("set-option", "-wu", "-t", tabId, "@forge_bell")
    }

    func capturePaneContent(id: String, lastN: Int) async -> String? {
        await runner.run("capture-pane", "-p", "-t", id, "-S", "-\(lastN)")
    }

    func startControlMode(
        onEvent: @escaping @Sendable (String) -> Void,
        onOutput: (@Sendable (String, Data) -> Void)?,
        onDisconnect: (@Sendable () -> Void)?,
        onReconnect: (@Sendable () -> Void)?
    ) {
        controlMode.start(onEvent: onEvent, onOutput: onOutput, onDisconnect: onDisconnect, onReconnect: onReconnect)
    }

    func stopControlMode() {
        controlMode.stop()
    }

    /// Detach all existing tmux clients before starting a fresh control mode session.
    /// Stale clients (from previous ForgeTerminalView attach or old control mode)
    /// constrain window sizes via the `window-size` option.
    func detachAllClients() async {
        guard let output = await runner.run("list-clients", "-F", "#{client_name}") else { return }
        for line in output.split(separator: "\n") {
            let name = line.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            _ = await runner.run("detach-client", "-t", name)
        }
    }

    // MARK: - Control Mode Pass-Through

    /// Direct pass-through to control mode for sub-ms latency commands (send-keys, resize-pane).
    /// Use this instead of runner.run() for interactive input during native rendering.
    func controlModeSend(_ command: String) {
        controlMode.send(command)
    }

    // MARK: - Session Snapshot

    func captureSessionSnapshot(project: String, path: String) async -> SessionSnapshot? {
        guard let tabOutput = await runner.run("list-windows", "-t", project, "-F", TmuxStateParser.snapshotTabFormat),
              let paneOutput = await runner.run("list-panes", "-s", "-t", project, "-F", TmuxStateParser.snapshotPaneFormat)
        else { return nil }

        let tabInfos = TmuxStateParser.parseSnapshotTabs(tabOutput)
        let paneInfos = TmuxStateParser.parseSnapshotPanes(paneOutput)
        let panesByWindow = Dictionary(grouping: paneInfos, by: \.windowIndex)

        let tabs = tabInfos.sorted(by: { $0.index < $1.index }).map { tab in
            let panes = (panesByWindow[tab.index] ?? []).sorted(by: { $0.index < $1.index }).map {
                PaneSnapshot(directory: $0.directory, index: $0.index)
            }
            let layout: String? = panes.count > 1 ? tab.layout : nil
            return TabSnapshot(name: tab.name, index: tab.index, layout: layout, panes: panes)
        }

        let canonical = URL(fileURLWithPath: path).standardized.path
        return SessionSnapshot(path: canonical, tabs: tabs)
    }

    // MARK: - Session Restore

    func restoreTab(session: String, name: String, directory: String) async -> String? {
        await runner.run("new-window", "-P", "-F", "#{window_id}", "-t", "\(session):", "-n", name, "-c", directory)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func restoreSplit(targetPane: String, direction: SplitDirection) async -> String? {
        let flag = direction == .horizontal ? "-h" : "-v"
        return await runner.run("split-window", flag, "-P", "-F", "#{pane_id}", "-t", targetPane)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func applyLayout(windowId: String, layout: String) async {
        _ = await runner.run("select-layout", "-t", windowId, layout)
    }

    func sendKeys(paneId: String, keys: String) async {
        _ = await runner.run("send-keys", "-t", paneId, keys, "Enter")
    }

    func renameWindow(target: String, name: String) async {
        _ = await runner.run("rename-window", "-t", target, name)
    }

    func listPaneIds(window: String) async -> [String] {
        guard let output = await runner.run("list-panes", "-t", window, "-F", "#{pane_id}") else { return [] }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").map(String.init)
    }

    // MARK: - Helpers

    // Wraps s in single quotes and escapes any embedded single quotes so the
    // resulting token is safe to embed in a tmux control-mode command string.
    // Example: "my 'proj'" → "'my '\\''proj'\\'''"
    private func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
