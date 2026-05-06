import Foundation
import Observation

public enum PaneStatus: String {
    case idle, running, needsAttention, error

    public static func from(command: String) -> PaneStatus {
        let lower = command.lowercased()
        let shells: Set<String> = ["zsh", "bash", "fish", "sh", "nu", "pwsh"]
        if lower.isEmpty || shells.contains(lower) {
            return .idle
        }
        return .running
    }
}

@Observable
@MainActor
public final class Pane: Identifiable {
    public let id: String
    public let tabId: String
    public var index: Int
    public var active: Bool
    public var currentCommand: String
    public var currentPath: String
    public var width: Int
    public var height: Int
    public var pid: Int
    public var status: PaneStatus
    public var hasBell: Bool = false
    public var hasContentMatch: Bool = false
    /// The command that was running before the most recent command change.
    public var previousCommand: String = ""

    /// True if this pane needs user attention (bell, content match, idle agent, error)
    public var needsAttention: Bool {
        hasBell || hasContentMatch || status == .needsAttention || status == .error
    }

    public init(id: String, tabId: String, index: Int = 0, active: Bool = false,
         currentCommand: String = "", currentPath: String = "",
         width: Int = 80, height: Int = 24, pid: Int = 0) {
        self.id = id
        self.tabId = tabId
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
