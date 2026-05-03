import Foundation
import Observation

enum PaneStatus: String {
    case idle, running, needsAttention, error

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
final class Pane: Identifiable {
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

    /// True if this pane needs user attention (bell, idle agent, error)
    var needsAttention: Bool {
        hasBell || status == .needsAttention || status == .error
    }

    init(id: String, windowId: String, index: Int, active: Bool = false,
         currentCommand: String = "", currentPath: String = "",
         width: Int = 80, height: Int = 24, pid: Int = 0) {
        self.id = id
        self.windowId = windowId
        self.index = index
        self.active = active
        self.currentCommand = currentCommand
        self.currentPath = currentPath
        self.width = width
        self.height = height
        self.pid = pid
        self.status = PaneStatus.from(command: currentCommand)
    }
}
