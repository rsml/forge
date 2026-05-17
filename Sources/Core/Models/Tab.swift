import Foundation
import Observation

@Observable
@MainActor
public final class Tab: Identifiable {
    public let id: String
    public let projectId: String
    /// Stable identifier used for attention tracking; never reassigned after init.
    public let uuid: UUID
    public var index: Int
    public var name: String
    public var active: Bool
    public var layout: String?
    /// Native PTY split tree — owned by Forge, not derived from tmux.
    public var splitTree: SplitNode?
    public var panes: [Pane] = []

    public var needsAttention: Bool {
        panes.contains { $0.needsAttention }
    }

    public init(id: String, projectId: String, index: Int, name: String, active: Bool = false, uuid: UUID = UUID()) {
        self.id = id
        self.projectId = projectId
        self.uuid = uuid
        self.index = index
        self.name = name
        self.active = active
    }
}
