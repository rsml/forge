import Foundation

public struct ProjectInfo {
    public let id: String
    public let name: String
    public let tabCount: Int
    public let attached: Bool
    public let path: String?

    public init(id: String, name: String, tabCount: Int, attached: Bool, path: String?) {
        self.id = id; self.name = name; self.tabCount = tabCount
        self.attached = attached; self.path = path
    }
}

public struct TabInfo {
    public let id: String
    public let projectId: String
    public let index: Int
    public let name: String
    public let active: Bool
    public let paneCount: Int
    public let hasBell: Bool

    public init(id: String, projectId: String, index: Int, name: String, active: Bool, paneCount: Int, hasBell: Bool = false) {
        self.id = id; self.projectId = projectId; self.index = index
        self.name = name; self.active = active; self.paneCount = paneCount
        self.hasBell = hasBell
    }
}

public struct PaneInfo {
    public let id: String
    public let tabId: String
    public let index: Int
    public let active: Bool
    public let currentCommand: String
    public let currentPath: String
    public let width: Int
    public let height: Int
    public let pid: Int

    public init(id: String, tabId: String, index: Int, active: Bool,
                currentCommand: String, currentPath: String,
                width: Int, height: Int, pid: Int) {
        self.id = id; self.tabId = tabId; self.index = index
        self.active = active; self.currentCommand = currentCommand
        self.currentPath = currentPath; self.width = width
        self.height = height; self.pid = pid
    }
}

public enum SplitDirection { case horizontal, vertical }

// MARK: - Focused Protocols

/// Read-only queries against tmux state.
@MainActor
public protocol TmuxQueryPort {
    func listProjects() async -> [ProjectInfo]
    func listTabs(project: String) async -> [TabInfo]
    func listAllTabs() async -> [TabInfo]
    func listPanes(tab: String) async -> [PaneInfo]
    func listAllPanes() async -> [PaneInfo]

    /// Capture the last N visible lines of a pane's terminal content.
    func capturePaneContent(id: String, lastN: Int) async -> String?
}

/// Mutation operations that change tmux state.
@MainActor
public protocol TmuxCommandPort {
    @discardableResult
    func newProject(name: String, path: String) async -> Bool
    func killProject(name: String) async
    func renameProject(target: String, newName: String) async

    func newTab(project: String, path: String?) async
    func killTab(id: String) async
    func selectTab(id: String) async
    func renameTab(id: String, newName: String) async

    func killPane(id: String) async
    func selectPane(id: String) async
    func switchClient(project: String) async

    func splitWindow(id: String, direction: SplitDirection) async
    func swapTab(id: String, offset: Int) async
    func reorderTab(id: String, swapWith: [String]) async
    func moveTab(id: String, toSession: String) async

    func sourceConfig(path: String) async
    func clearHistory(pane: String) async
    func clearBellFlag(tabId: String) async
}

/// Control mode lifecycle (starting/stopping the persistent tmux connection).
@MainActor
public protocol TmuxControlPort {
    var configPath: String? { get }

    func startControlMode(
        onEvent: @escaping @Sendable (String) -> Void,
        onDisconnect: (@Sendable () -> Void)?,
        onReconnect: (@Sendable () -> Void)?
    )
    func stopControlMode()
}

/// Convenience composition of all three tmux port protocols.
public typealias TmuxPort = TmuxQueryPort & TmuxCommandPort & TmuxControlPort
