import Foundation

public struct SessionInfo {
    public let id: String
    public let name: String
    public let windowCount: Int
    public let attached: Bool
    public let path: String?

    public init(id: String, name: String, windowCount: Int, attached: Bool, path: String?) {
        self.id = id; self.name = name; self.windowCount = windowCount
        self.attached = attached; self.path = path
    }
}

public struct WindowInfo {
    public let id: String
    public let sessionId: String
    public let index: Int
    public let name: String
    public let active: Bool
    public let paneCount: Int

    public init(id: String, sessionId: String, index: Int, name: String, active: Bool, paneCount: Int) {
        self.id = id; self.sessionId = sessionId; self.index = index
        self.name = name; self.active = active; self.paneCount = paneCount
    }
}

public struct PaneInfo {
    public let id: String
    public let windowId: String
    public let index: Int
    public let active: Bool
    public let currentCommand: String
    public let currentPath: String
    public let width: Int
    public let height: Int
    public let pid: Int

    public init(id: String, windowId: String, index: Int, active: Bool,
                currentCommand: String, currentPath: String,
                width: Int, height: Int, pid: Int) {
        self.id = id; self.windowId = windowId; self.index = index
        self.active = active; self.currentCommand = currentCommand
        self.currentPath = currentPath; self.width = width
        self.height = height; self.pid = pid
    }
}

public enum SplitDirection { case horizontal, vertical }

@MainActor
public protocol TmuxPort {
    func listSessions() async -> [SessionInfo]
    func listWindows(session: String) async -> [WindowInfo]
    func listAllWindows() async -> [WindowInfo]
    func listPanes(window: String) async -> [PaneInfo]
    func listAllPanes() async -> [PaneInfo]

    func newSession(name: String, path: String) async
    func killSession(name: String) async
    func renameSession(target: String, newName: String) async

    func newWindow(session: String, path: String?) async
    func killWindow(id: String) async
    func selectWindow(id: String) async
    func renameWindow(id: String, newName: String) async

    func killPane(id: String) async
    func selectPane(id: String) async
    func switchClient(session: String) async

    func splitWindow(id: String, direction: SplitDirection) async
    func swapWindow(id: String, offset: Int) async
    func reorderWindow(id: String, fromIndex: Int, toIndex: Int) async
    func moveWindow(id: String, toSession: String) async

    func sourceConfig(path: String) async
    func clearHistory(pane: String) async

    /// Capture the last N visible lines of a pane's terminal content.
    func capturePaneContent(id: String, lastN: Int) async -> String?

    func startControlMode(onEvent: @escaping @Sendable (String) -> Void)
    func stopControlMode()
}
