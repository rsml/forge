/// Pure index math for computing tab reorder swap targets.
/// No framework imports — fully testable without tmux.
public enum TabReordering {

    /// Compute the ordered list of tab IDs to swap with when moving a tab
    /// from `fromIndex` to `toIndex` in a list of the given count.
    ///
    /// `toIndex` uses the "insertion point" convention (same as `Array.move(fromOffsets:toOffset:)`):
    /// inserting before the element currently at `toIndex`. When moving forward,
    /// the final resting index is `toIndex - 1`.
    ///
    /// - Parameters:
    ///   - fromIndex: Current index of the tab being moved.
    ///   - toIndex: Insertion point (same semantics as `onMove`).
    ///   - ids: Ordered array of tab IDs in the current arrangement.
    /// - Returns: Ordered list of IDs to swap with, or empty if the move is a no-op.
    public static func swapTargets(fromIndex: Int, toIndex: Int, ids: [String]) -> [String] {
        guard fromIndex >= 0, fromIndex < ids.count else { return [] }

        let finalIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        guard finalIndex != fromIndex else { return [] }
        guard finalIndex >= 0, finalIndex < ids.count else { return [] }

        var targets: [String] = []
        if fromIndex < finalIndex {
            for i in (fromIndex + 1)...finalIndex {
                targets.append(ids[i])
            }
        } else {
            for i in stride(from: fromIndex - 1, through: finalIndex, by: -1) {
                targets.append(ids[i])
            }
        }
        return targets
    }
}
