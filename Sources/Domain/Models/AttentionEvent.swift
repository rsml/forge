import Foundation

/// Events that can place a window into the attention queue.
public enum AttentionEvent {
    case bell(windowUUID: UUID)
    case commandCompleted(windowUUID: UUID)

    public var windowUUID: UUID {
        switch self {
        case .bell(let id), .commandCompleted(let id): return id
        }
    }
}
