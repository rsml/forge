import Foundation
import Observation

@Observable
@MainActor
final class Window: Identifiable {
    let id: String
    let sessionId: String
    var index: Int
    var name: String
    var active: Bool
    var panes: [Pane] = []

    init(id: String, sessionId: String, index: Int, name: String, active: Bool = false) {
        self.id = id
        self.sessionId = sessionId
        self.index = index
        self.name = name
        self.active = active
    }
}
