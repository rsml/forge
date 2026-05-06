import Foundation

/// Events that can place a window into the attention queue.
public enum AttentionEvent: Sendable, Equatable {
    case bell(windowUUID: UUID)
    case commandCompleted(windowUUID: UUID)
    case contentMatch(windowUUID: UUID)

    public var windowUUID: UUID {
        switch self {
        case .bell(let id), .commandCompleted(let id), .contentMatch(let id): return id
        }
    }
}
