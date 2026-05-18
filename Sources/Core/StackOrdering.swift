import Foundation

/// Pure function that computes the attention queue order for stack mode.
public enum StackOrdering {

    public enum Mode: String, CaseIterable, Identifiable {
        case chronological
        case grouped
        case simple

        public var id: String { rawValue }
    }

    /// Returns the ordered list of tab UUIDs that need attention.
    ///
    /// - `frontUUID` is always first (even if it has no attention or is hidden).
    /// - Tabs that are hidden or have no attention are excluded (except `frontUUID`).
    /// - Ordering of the remainder depends on `mode`.
    @MainActor
    public static func order(
        projects: [Project],
        frontUUID: UUID,
        mode: Mode,
        timestamps: AttentionTimestamps,
        isHidden: (UUID) -> Bool
    ) -> [UUID] {
        var candidates: [(uuid: UUID, projectIndex: Int, tabIndex: Int)] = []
        for (pi, project) in projects.enumerated() {
            for (ti, tab) in project.tabs.enumerated() {
                guard tab.needsAttention,
                      !isHidden(tab.uuid),
                      tab.uuid != frontUUID else { continue }
                candidates.append((tab.uuid, pi, ti))
            }
        }

        let sorted: [UUID]
        switch mode {
        case .simple:
            sorted = candidates
                .sorted { ($0.projectIndex, $0.tabIndex) < ($1.projectIndex, $1.tabIndex) }
                .map(\.uuid)

        case .grouped:
            let frontProjectIndex = projects.firstIndex { project in
                project.tabs.contains { $0.uuid == frontUUID }
            } ?? 0
            sorted = candidates
                .sorted { a, b in
                    let aIsActive = a.projectIndex == frontProjectIndex
                    let bIsActive = b.projectIndex == frontProjectIndex
                    if aIsActive != bIsActive { return aIsActive }
                    if a.projectIndex != b.projectIndex { return a.projectIndex < b.projectIndex }
                    return a.tabIndex < b.tabIndex
                }
                .map(\.uuid)

        case .chronological:
            sorted = candidates
                .sorted { a, b in
                    let ta = timestamps.timestamp(for: a.uuid) ?? .distantFuture
                    let tb = timestamps.timestamp(for: b.uuid) ?? .distantFuture
                    if ta != tb { return ta < tb }
                    if a.projectIndex != b.projectIndex { return a.projectIndex < b.projectIndex }
                    return a.tabIndex < b.tabIndex
                }
                .map(\.uuid)
        }

        return [frontUUID] + sorted
    }
}
