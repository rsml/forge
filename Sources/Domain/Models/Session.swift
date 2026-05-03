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

    /// True if any window/pane in this session needs attention
    var needsAttention: Bool {
        windows.contains { $0.needsAttention }
    }

    init(id: String, name: String, windowCount: Int = 0, attached: Bool = false, path: String? = nil) {
        self.id = id
        self.name = name
        self.windowCount = windowCount
        self.attached = attached
        self.path = path
    }
}
