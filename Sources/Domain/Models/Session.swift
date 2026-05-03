import Foundation
import Observation

@Observable
@MainActor
final class Session: Identifiable {
    let id: String
    var name: String
    var windowCount: Int
    var attached: Bool
    var path: String?
    var windows: [Window] = []

    var aggregateStatus: PaneStatus {
        let all = windows.flatMap { $0.panes.map(\.status) }
        if all.contains(.needsAttention) { return .needsAttention }
        if all.contains(.error) { return .error }
        if all.contains(.running) { return .running }
        return .idle
    }

    init(id: String, name: String, windowCount: Int = 0, attached: Bool = false, path: String? = nil) {
        self.id = id
        self.name = name
        self.windowCount = windowCount
        self.attached = attached
        self.path = path
    }
}
