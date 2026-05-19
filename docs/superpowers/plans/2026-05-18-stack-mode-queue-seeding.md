# Stack Mode Queue Seeding & Ordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix stack mode so entering it seeds the attention queue with all attention-dotted tabs (not just the current one), add auto-pruning of resolved tabs, and add a configurable ordering setting (Chronological / Grouped / Simple).

**Architecture:** Three changes layered bottom-up: (1) attention timestamps + persistence in Core, (2) queue seeding + pruning logic in AttentionManager/orchestrator, (3) ordering setting in config + Settings UI. The ordering setting controls both the initial seed order and ongoing `handleEvent` insertion order.

**Tech Stack:** Swift 6.0, Swift Testing, SwiftUI (macOS 14+), ForgeCore SPM target.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `Sources/Core/Models/AttentionQueue.swift` | Add `allItems` accessor, `replaceAll` bulk setter |
| Create | `Sources/Core/Models/AttentionTimestamps.swift` | Pure `[UUID: Date]` store with persistence helpers |
| Create | `Sources/Core/StackOrdering.swift` | Pure function: given tabs + timestamps + ordering mode, return sorted `[UUID]` |
| Modify | `Sources/Core/Ports/AttentionPort.swift` | Add `timestamps`, `seedQueue`, `pruneResolved` to protocol |
| Modify | `Sources/Core/Models/AttentionEvent.swift` | No change needed — events already carry `tabUUID` |
| Modify | `Sources/Infrastructure/Config/ForgeConfig.swift` | Add `ordering` field to `StackViewSettings` |
| Modify | `Sources/Features/Attention/AttentionManager.swift` | Implement new protocol methods, store timestamps, persist them |
| Modify | `Sources/Features/Shared/AppState.swift` | Seed queue on `toggleMode` → stack |
| Modify | `Sources/WorkspaceController.swift` | Add pruning call in post-refresh hook |
| Modify | `Sources/Features/Settings/StackModeSettingsPane.swift` | Add ordering picker + description text |
| Create | `Tests/ForgeTests/StackOrderingTests.swift` | Tests for pure ordering logic |
| Create | `Tests/ForgeTests/AttentionTimestampsTests.swift` | Tests for timestamp store |
| Modify | `Tests/ForgeTests/AttentionQueueTests.swift` | Tests for new `allItems`, `replaceAll` |

---

### Task 1: AttentionQueue — add `allItems` and `replaceAll`

**Files:**
- Modify: `Sources/Core/Models/AttentionQueue.swift`
- Modify: `Tests/ForgeTests/AttentionQueueTests.swift`

- [ ] **Step 1: Write failing tests for `allItems` and `replaceAll`**

In `Tests/ForgeTests/AttentionQueueTests.swift`, add at the bottom before the closing `}`:

```swift
// MARK: - allItems

@Test("allItems returns items in queue order")
func testAllItems() {
    var q = AttentionQueue()
    let a = UUID(), b = UUID(), c = UUID()
    q.enqueue(a)
    q.enqueue(b)
    q.enqueue(c)
    #expect(q.allItems == [a, b, c])
}

@Test("allItems on empty queue returns empty array")
func testAllItemsEmpty() {
    let q = AttentionQueue()
    #expect(q.allItems.isEmpty)
}

// MARK: - replaceAll

@Test("replaceAll replaces entire queue contents")
func testReplaceAll() {
    var q = AttentionQueue()
    q.enqueue(UUID())
    q.enqueue(UUID())
    let a = UUID(), b = UUID()
    q.replaceAll([a, b])
    #expect(q.allItems == [a, b])
    #expect(q.count == 2)
    #expect(q.peek() == a)
}

@Test("replaceAll with empty array clears queue")
func testReplaceAllEmpty() {
    var q = AttentionQueue()
    q.enqueue(UUID())
    q.replaceAll([])
    #expect(q.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AttentionQueueTests`
Expected: FAIL — `allItems` and `replaceAll` not defined

- [ ] **Step 3: Implement `allItems` and `replaceAll`**

In `Sources/Core/Models/AttentionQueue.swift`, add after the `count` property (around line 60):

```swift
/// Returns all items in queue order (front to back).
public var allItems: [UUID] { items }

/// Replaces the entire queue with the given items.
public mutating func replaceAll(_ newItems: [UUID]) {
    items = newItems
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AttentionQueueTests`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/AttentionQueue.swift Tests/ForgeTests/AttentionQueueTests.swift
git commit -m "feat: add allItems and replaceAll to AttentionQueue"
```

---

### Task 2: AttentionTimestamps — pure timestamp store

**Files:**
- Create: `Sources/Core/Models/AttentionTimestamps.swift`
- Create: `Tests/ForgeTests/AttentionTimestampsTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/ForgeTests/AttentionTimestampsTests.swift`:

```swift
import Foundation
import Testing
@testable import ForgeCore

@Suite("AttentionTimestamps")
struct AttentionTimestampsTests {

    @Test("record stores timestamp for UUID")
    func testRecord() {
        var ts = AttentionTimestamps()
        let id = UUID()
        let now = Date()
        ts.record(id, at: now)
        #expect(ts.timestamp(for: id) == now)
    }

    @Test("record does not overwrite existing timestamp")
    func testRecordIdempotent() {
        var ts = AttentionTimestamps()
        let id = UUID()
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        ts.record(id, at: first)
        ts.record(id, at: second)
        #expect(ts.timestamp(for: id) == first)
    }

    @Test("remove deletes timestamp")
    func testRemove() {
        var ts = AttentionTimestamps()
        let id = UUID()
        ts.record(id, at: Date())
        ts.remove(id)
        #expect(ts.timestamp(for: id) == nil)
    }

    @Test("prune removes UUIDs not in valid set")
    func testPrune() {
        var ts = AttentionTimestamps()
        let a = UUID(), b = UUID(), c = UUID()
        ts.record(a, at: Date())
        ts.record(b, at: Date())
        ts.record(c, at: Date())
        ts.prune(validUUIDs: [a, c])
        #expect(ts.timestamp(for: a) != nil)
        #expect(ts.timestamp(for: b) == nil)
        #expect(ts.timestamp(for: c) != nil)
    }

    @Test("toDictionary and init(from:) round-trip")
    func testPersistence() {
        var ts = AttentionTimestamps()
        let a = UUID(), b = UUID()
        let d1 = Date(timeIntervalSince1970: 1000)
        let d2 = Date(timeIntervalSince1970: 2000)
        ts.record(a, at: d1)
        ts.record(b, at: d2)
        let dict = ts.toDictionary()
        let restored = AttentionTimestamps(from: dict)
        #expect(restored.timestamp(for: a) == d1)
        #expect(restored.timestamp(for: b) == d2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AttentionTimestampsTests`
Expected: FAIL — module has no type `AttentionTimestamps`

- [ ] **Step 3: Implement AttentionTimestamps**

Create `Sources/Core/Models/AttentionTimestamps.swift`:

```swift
import Foundation

/// Tracks when each tab first requested attention.
/// Pure value type — no framework dependencies.
public struct AttentionTimestamps {
    private var entries: [UUID: Date] = [:]

    public init() {}

    /// Restore from a persisted dictionary (UUID string → timeIntervalSince1970).
    public init(from dict: [String: Double]) {
        for (key, value) in dict {
            if let uuid = UUID(uuidString: key) {
                entries[uuid] = Date(timeIntervalSince1970: value)
            }
        }
    }

    /// Record attention time. No-op if already recorded (first event wins).
    public mutating func record(_ id: UUID, at date: Date = Date()) {
        guard entries[id] == nil else { return }
        entries[id] = date
    }

    /// Remove timestamp (e.g., on markDone).
    public mutating func remove(_ id: UUID) {
        entries.removeValue(forKey: id)
    }

    /// Look up the recorded timestamp.
    public func timestamp(for id: UUID) -> Date? {
        entries[id]
    }

    /// Remove entries not in the valid set.
    public mutating func prune(validUUIDs: some Collection<UUID>) {
        let valid = Set(validUUIDs)
        entries = entries.filter { valid.contains($0.key) }
    }

    /// Serialize for persistence.
    public func toDictionary() -> [String: Double] {
        var dict: [String: Double] = [:]
        for (uuid, date) in entries {
            dict[uuid.uuidString] = date.timeIntervalSince1970
        }
        return dict
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AttentionTimestampsTests`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/AttentionTimestamps.swift Tests/ForgeTests/AttentionTimestampsTests.swift
git commit -m "feat: add AttentionTimestamps pure value type"
```

---

### Task 3: StackOrdering — pure ordering function

**Files:**
- Create: `Sources/Core/StackOrdering.swift`
- Create: `Tests/ForgeTests/StackOrderingTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/ForgeTests/StackOrderingTests.swift`:

```swift
import Foundation
import Testing
@testable import ForgeCore

@Suite("StackOrdering")
@MainActor
struct StackOrderingTests {

    // Helper: build a minimal Tab with a pane that has needsAttention.
    // Uses Tab.init(uuid:) to inject deterministic UUIDs for assertions.
    private func attentionTab(uuid: UUID, projectId: String, index: Int) -> Tab {
        let tab = Tab(id: UUID().uuidString, projectId: projectId, index: index, name: "tab-\(index)", uuid: uuid)
        let pane = Pane(id: UUID().uuidString, tabId: tab.id, currentPath: "/tmp")
        pane.hasBell = true
        tab.panes.append(pane)
        return tab
    }

    // MARK: - Simple ordering

    @Test("simple mode: sidebar order — projects then tabs")
    func testSimpleOrdering() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        p1.tabs.append(attentionTab(uuid: b, projectId: "p1", index: 1))
        let p2 = Project(id: "p2", name: "beta", path: "/b")
        p2.tabs.append(attentionTab(uuid: c, projectId: "p2", index: 0))
        p2.tabs.append(attentionTab(uuid: d, projectId: "p2", index: 1))

        let result = StackOrdering.order(
            projects: [p1, p2],
            frontUUID: a,
            mode: .simple,
            timestamps: AttentionTimestamps(),
            isHidden: { _ in false }
        )
        #expect(result == [a, b, c, d])
    }

    // MARK: - Grouped ordering

    @Test("grouped mode: active project first, then others in sidebar order")
    func testGroupedOrdering() {
        let a = UUID(), b = UUID(), c = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        let p2 = Project(id: "p2", name: "beta", path: "/b")
        p2.tabs.append(attentionTab(uuid: b, projectId: "p2", index: 0))
        p2.tabs.append(attentionTab(uuid: c, projectId: "p2", index: 1))

        // frontUUID is in p2, so p2 should come first
        let result = StackOrdering.order(
            projects: [p1, p2],
            frontUUID: b,
            mode: .grouped,
            timestamps: AttentionTimestamps(),
            isHidden: { _ in false }
        )
        #expect(result == [b, c, a])
    }

    // MARK: - Chronological ordering

    @Test("chronological mode: earliest attention timestamp first")
    func testChronologicalOrdering() {
        let a = UUID(), b = UUID(), c = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        p1.tabs.append(attentionTab(uuid: b, projectId: "p1", index: 1))
        let p2 = Project(id: "p2", name: "beta", path: "/b")
        p2.tabs.append(attentionTab(uuid: c, projectId: "p2", index: 0))

        var ts = AttentionTimestamps()
        ts.record(a, at: Date(timeIntervalSince1970: 300))
        ts.record(b, at: Date(timeIntervalSince1970: 100)) // earliest
        ts.record(c, at: Date(timeIntervalSince1970: 200))

        let result = StackOrdering.order(
            projects: [p1, p2],
            frontUUID: a,
            mode: .chronological,
            timestamps: ts,
            isHidden: { _ in false }
        )
        // frontUUID always first, then chronological order of remaining
        #expect(result == [a, b, c])
    }

    // MARK: - Front UUID always first

    @Test("frontUUID is always first regardless of mode")
    func testFrontAlwaysFirst() {
        let a = UUID(), b = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        p1.tabs.append(attentionTab(uuid: b, projectId: "p1", index: 1))

        let result = StackOrdering.order(
            projects: [p1],
            frontUUID: b,
            mode: .simple,
            timestamps: AttentionTimestamps(),
            isHidden: { _ in false }
        )
        #expect(result.first == b)
    }

    // MARK: - Hidden tabs excluded

    @Test("hidden tabs are excluded from ordering")
    func testHiddenExcluded() {
        let a = UUID(), b = UUID(), c = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        p1.tabs.append(attentionTab(uuid: b, projectId: "p1", index: 1))
        p1.tabs.append(attentionTab(uuid: c, projectId: "p1", index: 2))

        let result = StackOrdering.order(
            projects: [p1],
            frontUUID: a,
            mode: .simple,
            timestamps: AttentionTimestamps(),
            isHidden: { $0 == b }
        )
        #expect(result == [a, c])
    }

    // MARK: - Non-attention tabs excluded

    @Test("tabs without needsAttention are excluded (except frontUUID)")
    func testNonAttentionExcluded() {
        let a = UUID(), b = UUID()
        let p1 = Project(id: "p1", name: "alpha", path: "/a")
        p1.tabs.append(attentionTab(uuid: a, projectId: "p1", index: 0))
        // b has no attention — pane must have a running command so status != .idle
        // (idle panes have needsAttention == true by default)
        let noAttentionTab = Tab(id: UUID().uuidString, projectId: "p1", index: 1, name: "busy", uuid: b)
        let busyPane = Pane(id: UUID().uuidString, tabId: noAttentionTab.id, currentCommand: "vim", currentPath: "/tmp")
        busyPane.status = .running
        noAttentionTab.panes.append(busyPane)
        p1.tabs.append(noAttentionTab)

        let result = StackOrdering.order(
            projects: [p1],
            frontUUID: a,
            mode: .simple,
            timestamps: AttentionTimestamps(),
            isHidden: { _ in false }
        )
        #expect(result == [a])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter StackOrderingTests`
Expected: FAIL — `StackOrdering` not defined

- [ ] **Step 3: Implement StackOrdering**

Create `Sources/Core/StackOrdering.swift`:

```swift
import Foundation

/// Pure function that computes the attention queue order for stack mode.
public enum StackOrdering {

    public enum Mode: String, CaseIterable, Identifiable {
        case chronological
        case grouped
        case simple

        public var id: String { rawValue }
    }

    /// Compute the ordered list of tab UUIDs for the stack queue.
    ///
    /// - Parameters:
    ///   - projects: All projects in sidebar order.
    ///   - frontUUID: The tab that should be first (currently selected).
    ///   - mode: The ordering mode.
    ///   - timestamps: Attention timestamps (used by `.chronological`).
    ///   - isHidden: Predicate returning true for hidden tabs.
    /// - Returns: Ordered array of tab UUIDs. `frontUUID` is always first.
    public static func order(
        projects: [Project],
        frontUUID: UUID,
        mode: Mode,
        timestamps: AttentionTimestamps,
        isHidden: (UUID) -> Bool
    ) -> [UUID] {
        // Collect all attention tabs (not hidden), excluding frontUUID
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
            // Sidebar order: project index, then tab index
            sorted = candidates
                .sorted { ($0.projectIndex, $0.tabIndex) < ($1.projectIndex, $1.tabIndex) }
                .map(\.uuid)

        case .grouped:
            // Find which project frontUUID belongs to
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
                    // Tie-break: sidebar order
                    if a.projectIndex != b.projectIndex { return a.projectIndex < b.projectIndex }
                    return a.tabIndex < b.tabIndex
                }
                .map(\.uuid)
        }

        return [frontUUID] + sorted
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter StackOrderingTests`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/StackOrdering.swift Tests/ForgeTests/StackOrderingTests.swift
git commit -m "feat: add StackOrdering pure function with three modes"
```

---

### Task 4: Config — add `ordering` field to `StackViewSettings`

**Files:**
- Modify: `Sources/Infrastructure/Config/ForgeConfig.swift:97-107`

- [ ] **Step 1: Add ordering field**

In `ForgeConfig.StackViewSettings` (line 97), add after `contentPatterns`:

```swift
var ordering: String?               // "chronological" | "grouped" | "simple" (default "grouped")
var attentionTimestamps: [String: Double]?  // UUID string → timeIntervalSince1970
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: SUCCESS (field is optional, Codable auto-synthesizes)

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Config/ForgeConfig.swift
git commit -m "feat: add ordering and attentionTimestamps to StackViewSettings config"
```

---

### Task 5: AttentionPort — add new protocol methods

**Files:**
- Modify: `Sources/Core/Ports/AttentionPort.swift`

- [ ] **Step 1: Add `seedQueue` and `pruneResolved` to protocol**

Add at the end of the protocol, before the closing `}`:

```swift
/// Attention timestamps for ordering (read-only).
var timestamps: AttentionTimestamps { get }

/// Seed the queue with ordered UUIDs (e.g., on entering stack mode).
func seedQueue(ordered: [UUID])

/// Remove tabs from the queue whose attention has resolved,
/// except the front item (currently viewed).
func pruneResolved(activeAttentionUUIDs: Set<UUID>)
```

- [ ] **Step 2: Verify build fails (AttentionManager doesn't conform yet)**

Run: `swift build`
Expected: FAIL — AttentionManager missing `seedQueue` and `pruneResolved`

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/Ports/AttentionPort.swift
git commit -m "feat: add seedQueue and pruneResolved to AttentionPort"
```

---

### Task 6: AttentionManager — implement new protocol, timestamps, persistence

**Files:**
- Modify: `Sources/Features/Attention/AttentionManager.swift`

- [ ] **Step 1: Add timestamp storage and new methods**

Add a `timestamps` property and implement the new protocol methods. Replace the full file content:

```swift
import Foundation
import Observation
import AppKit
import ForgeCore

@Observable @MainActor
final class AttentionManager: AttentionPort {
    private var queue = AttentionQueue()
    private(set) var hiddenSet: Set<UUID> = []
    var timestamps = AttentionTimestamps()
    private let notifier: any NotificationPort
    private let config: ForgeConfigStore

    var currentTabUUID: UUID? { queue.peek() }
    var nextWindowUUID: UUID? { queue.peekSecond() }
    var queueCount: Int { queue.count }

    init(notifier: any NotificationPort, config: ForgeConfigStore) {
        self.notifier = notifier
        self.config = config
        self.hiddenSet = loadHiddenSet(from: config)
        self.timestamps = loadTimestamps(from: config)
    }

    func pruneStaleHiddenEntries(validUUIDs: Set<UUID>) {
        let stale = hiddenSet.subtracting(validUUIDs)
        if !stale.isEmpty {
            hiddenSet.subtract(stale)
            persistHiddenSet()
        }
        timestamps.prune(validUUIDs: validUUIDs)
        persistTimestamps()
    }

    func handleEvent(_ event: AttentionEvent) {
        let uuid = event.tabUUID
        guard !hiddenSet.contains(uuid) else { return }
        timestamps.record(uuid)
        queue.enqueue(uuid)

        if config.config.stackView?.bringToForeground == "always" {
            NSApp.activate()
        }
    }

    func markDone(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        timestamps.remove(tabUUID)
        persistTimestamps()
    }

    func hide(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        hiddenSet.insert(tabUUID)
        persistHiddenSet()
    }

    func moveToBack(_ tabUUID: UUID) {
        queue.moveToBack(tabUUID)
    }

    func unhide(_ tabUUID: UUID) {
        hiddenSet.remove(tabUUID)
        persistHiddenSet()
    }

    func removeTab(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        hiddenSet.remove(tabUUID)
        timestamps.remove(tabUUID)
    }

    func isHidden(_ tabUUID: UUID) -> Bool {
        hiddenSet.contains(tabUUID)
    }

    func promoteToFront(_ tabUUID: UUID) {
        queue.remove(tabUUID)
        queue.insertAtFront(tabUUID)
    }

    func seedQueue(ordered: [UUID]) {
        queue.replaceAll(ordered)
    }

    func pruneResolved(activeAttentionUUIDs: Set<UUID>) {
        let front = queue.peek()
        let toRemove = queue.allItems.filter { $0 != front && !activeAttentionUUIDs.contains($0) }
        for uuid in toRemove {
            queue.remove(uuid)
            timestamps.remove(uuid)
        }
        if !toRemove.isEmpty { persistTimestamps() }
    }

    // MARK: - Persistence

    private func persistHiddenSet() {
        let uuids = hiddenSet.map(\.uuidString)
        config.update { config in
            if config.stackView == nil {
                config.stackView = ForgeConfig.StackViewSettings()
            }
            config.stackView?.hiddenTabUUIDs = uuids
        }
    }

    private func persistTimestamps() {
        let dict = timestamps.toDictionary()
        config.update { config in
            if config.stackView == nil {
                config.stackView = ForgeConfig.StackViewSettings()
            }
            config.stackView?.attentionTimestamps = dict
        }
    }

    private func loadHiddenSet(from config: ForgeConfigStore) -> Set<UUID> {
        Set((config.config.stackView?.hiddenTabUUIDs ?? []).compactMap(UUID.init))
    }

    private func loadTimestamps(from config: ForgeConfigStore) -> AttentionTimestamps {
        guard let dict = config.config.stackView?.attentionTimestamps else {
            return AttentionTimestamps()
        }
        return AttentionTimestamps(from: dict)
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: SUCCESS

- [ ] **Step 3: Run all tests**

Run: `swift test`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/Features/Attention/AttentionManager.swift
git commit -m "feat: AttentionManager — timestamps, seedQueue, pruneResolved"
```

---

### Task 7: Seed queue on entering stack mode

**Files:**
- Modify: `Sources/Features/Shared/AppState.swift:93-113` (the `toggleMode` case)

- [ ] **Step 1: Update toggleMode to seed queue**

Replace the `.toggleMode` case (lines 93-113) with:

```swift
case .toggleMode:
    if config.isStackMode {
        // Switching TO list mode — restore active project/tab from queue front
        if let uuid = attentionManager?.currentTabUUID,
           let (project, tab) = controller.workspace.findTab(byUUID: uuid) {
            controller.workspace.activeProjectId = project.id
            controller.workspace.activeTabId = tab.id
        }
        config.isStackMode = false
    } else {
        // Switching TO stack mode — seed the queue with all attention tabs
        let frontUUID: UUID? = {
            if let tabId = controller.workspace.activeTabId,
               let tab = controller.workspace.activeProject?.tabs.first(where: { $0.id == tabId }) {
                return tab.uuid
            }
            return nil
        }()

        if let frontUUID, let attention = attentionManager {
            let orderingRaw = config.config.stackView?.ordering ?? "grouped"
            let mode = StackOrdering.Mode(rawValue: orderingRaw) ?? .grouped
            let ordered = StackOrdering.order(
                projects: controller.workspace.projects,
                frontUUID: frontUUID,
                mode: mode,
                timestamps: attention.timestamps,
                isHidden: { attention.isHidden($0) }
            )
            attention.seedQueue(ordered: ordered)
        }

        config.isStackMode = true
        if let uuid = attentionManager?.currentTabUUID,
           let (_, tab) = controller.workspace.findTab(byUUID: uuid) {
            controller.selectTab(tab)
        }
    }
    onModeChanged?()
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add Sources/Features/Shared/AppState.swift
git commit -m "feat: seed attention queue with all attention tabs on entering stack mode"
```

---

### Task 8: Add pruning in post-refresh hook

**Files:**
- Modify: `Sources/WorkspaceController.swift:152-171` (the `setPostRefreshHook` closure)

- [ ] **Step 1: Add pruning call after event processing**

In the `connectTmux()` method, inside `setPostRefreshHook`, after the existing `for event in events` loop (after line 168) and before `self.updateRenderers()` (line 171), add:

```swift
// Prune queue items whose attention resolved (except front item)
if self.config.isStackMode {
    let activeUUIDs = Set(
        self.workspace.projects
            .flatMap(\.tabs)
            .filter(\.needsAttention)
            .map(\.uuid)
    )
    self.attentionManager?.pruneResolved(activeAttentionUUIDs: activeUUIDs)
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add Sources/WorkspaceController.swift
git commit -m "feat: prune resolved attention items from stack queue on refresh"
```

---

### Task 9: Settings UI — ordering picker with descriptions

**Files:**
- Modify: `Sources/Features/Settings/StackModeSettingsPane.swift`

- [ ] **Step 1: Add ordering section**

In `StackModeSettingsPane`, add a new `Section("Ordering")` between the "Layout" and "Attention" sections. Replace the full file:

```swift
import SwiftUI
import ForgeCore

struct StackModeSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    private var orderingMode: String {
        store.config.stackView?.ordering ?? "grouped"
    }

    private var orderingDescription: String {
        switch orderingMode {
        case "chronological":
            return "Orders the stack by when each tab requested attention, earliest first."
        case "simple":
            return "Orders the stack by project and tab position — first project first, first tab first."
        default:
            return "Reduces context switching by grouping tabs from the same project together."
        }
    }

    var body: some View {
        Form {
            Section {
                Text("Stack mode displays sessions as a single vertical stack without a sidebar — focused on one project at a time.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Layout") {
                Picker("Toolbar position", selection: stackBinding(\.toolbarPosition, default: "bottom")) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, -4)
            }

            Section("Ordering") {
                Picker("Stack ordering", selection: stackBinding(\.ordering, default: "grouped")) {
                    Text("Chronological").tag("chronological")
                    Text("Grouped").tag("grouped")
                    Text("Simple").tag("simple")
                }
                .padding(.vertical, -4)

                Text(orderingDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .animation(.none, value: orderingMode)
            }

            Section("Attention") {
                Picker("Bring to foreground", selection: stackBinding(\.bringToForeground, default: "never")) {
                    Text("Never").tag("never")
                    Text("Always").tag("always")
                }
                .padding(.vertical, -4)

                Picker("Notify", selection: stackBinding(\.notify, default: "never")) {
                    Text("Never").tag("never")
                    Text("Always").tag("always")
                }
                .padding(.vertical, -4)

                Toggle(isOn: stackBinding(\.notifyInStackMode, default: false)) {
                    Text("Show notifications in stack mode")
                    Text("Recommended off. Stack mode always shows tabs that need attention in order, so notifications are usually unnecessary.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, -4)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stackBinding<T>(_ keyPath: WritableKeyPath<ForgeConfig.StackViewSettings, T?>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: { store.config.stackView?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                store.update { config in
                    if config.stackView == nil { config.stackView = ForgeConfig.StackViewSettings() }
                    config.stackView![keyPath: keyPath] = newValue
                }
            }
        )
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build`
Expected: SUCCESS

- [ ] **Step 3: Commit**

```bash
git add Sources/Features/Settings/StackModeSettingsPane.swift
git commit -m "feat: stack ordering picker in settings with contextual descriptions"
```

---

### Task 10: Integration verification

- [ ] **Step 1: Run full test suite**

Run: `swift test`
Expected: ALL PASS

- [ ] **Step 2: Build release**

Run: `swift build -c release`
Expected: SUCCESS

- [ ] **Step 3: Manual smoke test (if app can be launched)**

Run: `make dev`
Then:
1. Open Settings → Stack Mode tab → verify ordering picker appears with "Grouped" selected and description text
2. Create 3 tabs, trigger attention on all 3 (e.g., run a command that completes)
3. Switch to stack mode → verify all 3 appear in queue (not just the selected one)
4. Press cmd+enter to dismiss → verify next tab appears (not empty state)
5. Switch ordering to "Simple", toggle modes again → verify sidebar order
6. Switch ordering to "Chronological" → verify timestamp-based order

- [ ] **Step 4: Final commit if any adjustments needed**

```bash
git add -A
git commit -m "fix: stack mode queue seeding and ordering"
```
