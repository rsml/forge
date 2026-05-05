import Foundation
import Observation

@Observable
@MainActor
public final class Session: Identifiable {
    public let id: String
    public var name: String
    public var windowCount: Int
    public var attached: Bool
    public var path: String?
    public var windows: [Window] = []

    /// True if any window/pane in this session needs attention
    public var needsAttention: Bool {
        windows.contains { $0.needsAttention }
    }

    public init(id: String, name: String, windowCount: Int = 0, attached: Bool = false, path: String? = nil) {
        self.id = id
        self.name = name
        self.windowCount = windowCount
        self.attached = attached
        self.path = path
    }
}
