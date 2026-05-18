import Foundation

/// Snapshot of a single pane's foreground activity.
///
/// `command` is the basename of the foreground process's binary path
/// (e.g. `/usr/bin/vim` → `vim`). It is `nil` when the pane is idle
/// or when the lookup failed (in which case callers should substitute
/// a generic phrase such as `"a process"`).
public struct PaneActivity: Sendable {
    public let paneId: String
    public let isActive: Bool
    public let command: String?

    public init(paneId: String, isActive: Bool, command: String?) {
        self.paneId = paneId
        self.isActive = isActive
        self.command = command
    }
}

/// Reports which panes currently have a foreground process other than
/// the controlling shell. Implementations are expected to fail open —
/// returning all-idle results on error — so a flaky backend cannot block
/// a close operation.
public protocol PaneActivityPort: Sendable {
    func query(paneIds: [String]) async -> [PaneActivity]
}
