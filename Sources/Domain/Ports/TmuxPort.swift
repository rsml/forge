import Foundation

struct SessionInfo {
    let id: String
    let name: String
    let windowCount: Int
    let attached: Bool
    let path: String?
}

struct WindowInfo {
    let id: String
    let sessionId: String
    let index: Int
    let name: String
    let active: Bool
    let paneCount: Int
}

struct PaneInfo {
    let id: String
    let windowId: String
    let index: Int
    let active: Bool
    let currentCommand: String
    let currentPath: String
    let width: Int
    let height: Int
    let pid: Int
}

enum SplitDirection { case horizontal, vertical }

@MainActor
protocol TmuxPort {
    func listSessions() async -> [SessionInfo]
    func listWindows(session: String) async -> [WindowInfo]
    func listPanes(window: String) async -> [PaneInfo]

    func newSession(name: String, path: String) async
    func killSession(name: String) async
    func renameSession(target: String, newName: String) async

    func newWindow(session: String, path: String?) async
    func killWindow(id: String) async
    func selectWindow(id: String) async
    func renameWindow(id: String, newName: String) async

    func selectPane(id: String) async
    func switchClient(session: String) async

    func splitWindow(id: String, direction: SplitDirection) async
    func swapWindow(id: String, offset: Int) async

    func startControlMode(onEvent: @escaping @Sendable (String) -> Void)
    func stopControlMode()
}
