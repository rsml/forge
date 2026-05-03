import Foundation
import Observation

/// Represents the full tmux server state as observed by Forge.
/// tmux is the source of truth — this is a read model.
@Observable
@MainActor
final class TmuxState {
    var sessions: [TmuxSession] = []
    var activeSessionId: String?
    var activeWindowId: String?
    var activePaneId: String?
    var connected: Bool = false

    var activeSession: TmuxSession? {
        sessions.first { $0.id == activeSessionId }
    }

    func session(byId id: String) -> TmuxSession? {
        sessions.first { $0.id == id }
    }

    func updateFromList(sessions raw: [TmuxSessionInfo]) {
        var updated: [TmuxSession] = []
        for info in raw {
            if let existing = session(byId: info.id) {
                existing.update(from: info)
                updated.append(existing)
            } else {
                updated.append(TmuxSession(from: info))
            }
        }
        sessions = updated
    }
}

// MARK: - Raw info structs (parsed from tmux output)

struct TmuxSessionInfo {
    let id: String
    let name: String
    let windowCount: Int
    let attached: Bool
    let path: String?
}

struct TmuxWindowInfo {
    let id: String
    let sessionId: String
    let index: Int
    let name: String
    let active: Bool
    let paneCount: Int
}

struct TmuxPaneInfo {
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

// MARK: - Observable model objects

@Observable
@MainActor
final class TmuxSession: Identifiable {
    let id: String
    var name: String
    var windowCount: Int
    var attached: Bool
    var path: String?
    var windows: [TmuxWindow] = []

    var aggregateStatus: PaneStatus {
        let allStatuses = windows.flatMap { $0.panes.map(\.status) }
        if allStatuses.contains(.needsAttention) { return .needsAttention }
        if allStatuses.contains(.error) { return .error }
        if allStatuses.contains(.running) { return .running }
        return .idle
    }

    init(from info: TmuxSessionInfo) {
        self.id = info.id
        self.name = info.name
        self.windowCount = info.windowCount
        self.attached = info.attached
        self.path = info.path
    }

    func update(from info: TmuxSessionInfo) {
        name = info.name
        windowCount = info.windowCount
        attached = info.attached
        path = info.path
    }
}

@Observable
@MainActor
final class TmuxWindow: Identifiable {
    let id: String
    let sessionId: String
    var index: Int
    var name: String
    var active: Bool
    var panes: [TmuxPane] = []

    init(from info: TmuxWindowInfo) {
        self.id = info.id
        self.sessionId = info.sessionId
        self.index = info.index
        self.name = info.name
        self.active = info.active
    }

    func update(from info: TmuxWindowInfo) {
        index = info.index
        name = info.name
        active = info.active
    }
}

enum PaneStatus: String {
    case idle
    case running
    case needsAttention
    case error

    static func from(command: String) -> PaneStatus {
        let lower = command.lowercased()
        if lower.isEmpty || lower == "zsh" || lower == "bash" || lower == "fish" {
            return .idle
        }
        return .running
    }
}

@Observable
@MainActor
final class TmuxPane: Identifiable {
    let id: String
    let windowId: String
    var index: Int
    var active: Bool
    var currentCommand: String
    var currentPath: String
    var width: Int
    var height: Int
    var pid: Int
    var status: PaneStatus
    var hasBell: Bool = false

    init(from info: TmuxPaneInfo) {
        self.id = info.id
        self.windowId = info.windowId
        self.index = info.index
        self.active = info.active
        self.currentCommand = info.currentCommand
        self.currentPath = info.currentPath
        self.width = info.width
        self.height = info.height
        self.pid = info.pid
        self.status = PaneStatus.from(command: info.currentCommand)
    }

    func update(from info: TmuxPaneInfo) {
        index = info.index
        active = info.active
        currentCommand = info.currentCommand
        currentPath = info.currentPath
        width = info.width
        height = info.height
        pid = info.pid
        status = hasBell ? .needsAttention : PaneStatus.from(command: info.currentCommand)
    }
}
