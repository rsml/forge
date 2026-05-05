import Foundation
import Observation

@Observable
@MainActor
public final class Window: Identifiable {
    public let id: String
    public let sessionId: String
    /// Stable identifier used for attention tracking; never reassigned after init.
    public let uuid: UUID
    public var index: Int
    public var name: String
    public var active: Bool
    public var panes: [Pane] = []

    public var needsAttention: Bool {
        panes.contains { $0.needsAttention }
    }

    public init(id: String, sessionId: String, index: Int, name: String, active: Bool = false, uuid: UUID = UUID()) {
        self.id = id
        self.sessionId = sessionId
        self.uuid = uuid
        self.index = index
        self.name = name
        self.active = active
    }
}
