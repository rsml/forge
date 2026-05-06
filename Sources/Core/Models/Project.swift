import Foundation
import Observation

@Observable
@MainActor
public final class Project: Identifiable {
    public let id: String
    public var name: String
    public var tabCount: Int
    public var attached: Bool
    public var path: String?
    public var tabs: [Tab] = []

    /// True if any tab/pane in this project needs attention
    public var needsAttention: Bool {
        tabs.contains { $0.needsAttention }
    }

    public init(id: String, name: String, tabCount: Int = 0, attached: Bool = false, path: String? = nil) {
        self.id = id
        self.name = name
        self.tabCount = tabCount
        self.attached = attached
        self.path = path
    }
}
