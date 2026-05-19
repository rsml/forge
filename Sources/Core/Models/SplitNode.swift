import Foundation

/// Orientation for a pane split.
public enum SplitDirection: Sendable, Equatable {
    case horizontal
    case vertical
}

/// Tree of pane splits within a Tab. Each leaf corresponds to a Pane,
/// in the same order as `Tab.panes`. Internal nodes carry their direction
/// and child proportions (sum to ~1.0).
public enum SplitNode: Sendable {
    case leaf
    case split(SplitDirection, [SplitNode], proportions: [CGFloat])

    public var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, let children, _): return children.reduce(0) { $0 + $1.leafCount }
        }
    }
}

// Equatable ignores proportions — topology-only comparison.
extension SplitNode: Equatable {
    public static func == (lhs: SplitNode, rhs: SplitNode) -> Bool {
        switch (lhs, rhs) {
        case (.leaf, .leaf): return true
        case let (.split(d1, c1, _), .split(d2, c2, _)):
            return d1 == d2 && c1 == c2
        default: return false
        }
    }
}
