import Foundation

/// Events that can place a tab into the attention queue.
public enum AttentionEvent: Sendable, Equatable {
    case bell(tabUUID: UUID)
    case commandCompleted(tabUUID: UUID)
    case contentMatch(tabUUID: UUID)

    public var tabUUID: UUID {
        switch self {
        case .bell(let id), .commandCompleted(let id), .contentMatch(let id): return id
        }
    }
}
