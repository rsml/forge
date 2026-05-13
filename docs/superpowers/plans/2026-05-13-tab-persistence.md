# Tab Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Save and restore tab/pane layout when reopening a project at the same folder path.

**Architecture:** Snapshot tab structure to `~/.config/forge/sessions/<hash>.json` on project close, restore from snapshot on project open. Layout parser in Core decodes tmux's `window_layout` tree for deterministic multi-pane restore.

**Tech Stack:** Swift 6.0, CryptoKit (SHA256), Swift Testing, ForgeCore SPM target

**Spec:** `docs/superpowers/specs/2026-05-13-tab-persistence-design.md`

---

### Task 1: SessionSnapshot data model

**Files:**
- Create: `Sources/Core/Models/SessionSnapshot.swift`

- [ ] **Step 1: Create the snapshot types**

```swift
import Foundation

public struct SessionSnapshot: Codable {
    public let path: String
    public let savedAt: Date
    public let tabs: [TabSnapshot]

    public init(path: String, savedAt: Date = Date(), tabs: [TabSnapshot]) {
        self.path = path
        self.savedAt = savedAt
        self.tabs = tabs
    }
}

public struct TabSnapshot: Codable {
    public let name: String
    public let index: Int
    public let layout: String?
    public let panes: [PaneSnapshot]

    public init(name: String, index: Int, layout: String?, panes: [PaneSnapshot]) {
        self.name = name
        self.index = index
        self.layout = layout
        self.panes = panes
    }
}

public struct PaneSnapshot: Codable {
    public let directory: String
    public let index: Int

    public init(directory: String, index: Int) {
        self.directory = directory
        self.index = index
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/Core/Models/SessionSnapshot.swift
git commit -m "feat: add SessionSnapshot data model"
```

---

### Task 2: LayoutParser — parse tmux window_layout into split tree (TDD)

**Files:**
- Create: `Sources/Core/LayoutParser.swift`
- Create: `Tests/ForgeTests/LayoutParserTests.swift`

The tmux `window_layout` format: `<checksum>,<WxH>,<X>,<Y>,<pane_id>` for leaves, `{...}` for horizontal splits, `[...]` for vertical splits. The parser extracts the split tree structure — we only need the topology (split direction + leaf count), not dimensions.

- [ ] **Step 1: Write failing tests**

```swift
import Testing
@testable import ForgeCore

@Suite("LayoutParser")
struct LayoutParserTests {

    @Test("single pane returns a leaf")
    func singlePane() {
        let node = LayoutParser.parse("ab12,190x50,0,0,1")
        #expect(node == .leaf)
    }

    @Test("horizontal split returns two children")
    func horizontalSplit() {
        // {left,right} = horizontal (side by side)
        let node = LayoutParser.parse("ab12,190x50,0,0{95x50,0,0,1,95x50,96,0,2}")
        #expect(node == .split(.horizontal, [.leaf, .leaf]))
    }

    @Test("vertical split returns two children")
    func verticalSplit() {
        // [top,bottom] = vertical (stacked)
        let node = LayoutParser.parse("ab12,190x50,0,0[190x25,0,0,1,190x24,0,26,2]")
        #expect(node == .split(.vertical, [.leaf, .leaf]))
    }

    @Test("nested splits")
    func nestedSplits() {
        // Horizontal root: left leaf, right is vertical split with two leaves
        let node = LayoutParser.parse("ab12,190x50,0,0{95x50,0,0,1[47x25,0,0,2,47x24,0,26,3]}")
        #expect(node == .split(.horizontal, [.leaf, .split(.vertical, [.leaf, .leaf])]))
    }

    @Test("three-way horizontal split")
    func threeWayHorizontal() {
        let node = LayoutParser.parse("ab12,270x50,0,0{90x50,0,0,1,90x50,91,0,2,90x50,182,0,3}")
        #expect(node == .split(.horizontal, [.leaf, .leaf, .leaf]))
    }

    @Test("leaf count matches pane count")
    func leafCount() {
        let node = LayoutParser.parse("ab12,190x50,0,0{95x50,0,0,1[47x25,0,0,2,47x24,0,26,3]}")
        #expect(node.leafCount == 3)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LayoutParser 2>&1 | tail -5`
Expected: Compilation error — `LayoutParser` does not exist

- [ ] **Step 3: Implement LayoutParser**

```swift
import Foundation

public enum SplitNode: Equatable, Sendable {
    case leaf
    case split(SplitDirection, [SplitNode])

    public var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, let children): return children.reduce(0) { $0 + $1.leafCount }
        }
    }
}

public enum LayoutParser {
    /// Parse a tmux window_layout string into a split tree.
    /// Format: `<checksum>,<WxH>,<X>,<Y>,<content>`
    /// where content is a pane ID (leaf) or `{...}` / `[...]` (split).
    public static func parse(_ layout: String) -> SplitNode {
        // Skip the checksum prefix (4 hex chars + comma)
        guard let commaIdx = layout.firstIndex(of: ",") else { return .leaf }
        let body = String(layout[layout.index(after: commaIdx)...])
        return parseNode(body[body.startIndex...])
    }

    private static func parseNode(_ s: Substring) -> SplitNode {
        // Find the split bracket: scan for `{` or `[` that starts the split content.
        // Layout: `WxH,X,Y,<pane_id>` or `WxH,X,Y{...}` or `WxH,X,Y[...]`
        if let braceIdx = findSplitStart(s) {
            let ch = s[braceIdx]
            let direction: SplitDirection = ch == "{" ? .horizontal : .vertical
            let close: Character = ch == "{" ? "}" : "]"
            let inner = extractBracketed(s, from: braceIdx, open: ch, close: close)
            let children = splitChildren(inner).map { parseNode($0) }
            return .split(direction, children)
        }
        return .leaf
    }

    /// Find the index of `{` or `[` that starts the split content, skipping the dimension prefix.
    private static func findSplitStart(_ s: Substring) -> String.Index? {
        s.firstIndex(where: { $0 == "{" || $0 == "[" })
    }

    /// Extract content between matching brackets.
    /// Tracks depth using any `{[` as open and `}]` as close — tmux layout
    /// strings never mix bracket types at the same nesting level.
    private static func extractBracketed(_ s: Substring, from idx: String.Index, open: Character, close: Character) -> Substring {
        let start = s.index(after: idx)
        var depth = 1
        var cur = start
        while cur < s.endIndex {
            let ch = s[cur]
            if ch == "{" || ch == "[" { depth += 1 }
            else if ch == "}" || ch == "]" { depth -= 1 }
            if depth == 0 { return s[start..<cur] }
            cur = s.index(after: cur)
        }
        return s[start..<s.endIndex]
    }

    /// Split children at top-level commas (not inside nested brackets).
    private static func splitChildren(_ s: Substring) -> [Substring] {
        var results: [Substring] = []
        var depth = 0
        var start = s.startIndex
        // Children are separated by commas at depth 0, but each child starts with `WxH,X,Y,...`
        // so we need to find commas that separate children (which are after a pane_id or closing bracket)
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "{" || ch == "[" { depth += 1 }
            if ch == "}" || ch == "]" { depth -= 1 }
            if ch == "," && depth == 0 {
                // Check if this comma separates children: the next char should start a dimension (digit)
                let next = s.index(after: i)
                if next < s.endIndex && s[next].isNumber {
                    // Check if previous char was a digit (pane_id) or closing bracket
                    let prev = s.index(before: i)
                    if s[prev].isNumber || s[prev] == "}" || s[prev] == "]" {
                        results.append(s[start..<i])
                        start = next
                    }
                }
            }
            i = s.index(after: i)
        }
        results.append(s[start..<s.endIndex])
        return results
    }
}
```

Note: The bracket matching logic above is a starting point. The implementer should verify against real tmux layout strings. The key insight is that children within `{...}` or `[...]` are separated by commas where the next token starts with a dimension like `95x50`. The parser only needs to extract the tree topology — dimensions are discarded.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LayoutParser 2>&1 | tail -10`
Expected: All 6 tests pass

- [ ] **Step 5: Fix any failing tests and iterate**

The `splitChildren` logic for parsing tmux layout strings is tricky. Use real tmux output to calibrate. You can get real layout strings by running:
```bash
tmux -L forge list-windows -F "#{window_layout}"
```
Adjust the parser until all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/LayoutParser.swift Tests/ForgeTests/LayoutParserTests.swift
git commit -m "feat: add LayoutParser for tmux window_layout strings"
```

---

### Task 3: SessionSnapshotStore — file I/O for snapshots

**Files:**
- Create: `Sources/Infrastructure/Config/SessionSnapshotStore.swift`

- [ ] **Step 1: Implement the store**

```swift
import Foundation
import CryptoKit
import ForgeCore

enum SessionSnapshotStore {
    private static var sessionsDir: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/forge/sessions")
    }

    static func save(_ snapshot: SessionSnapshot) {
        let url = fileURL(for: snapshot.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else {
            ForgeLog.log("[app] Failed to encode session snapshot for \(snapshot.path)")
            return
        }
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        do {
            try data.write(to: url)
            ForgeLog.log("[app] Saved session snapshot: \(url.lastPathComponent)")
        } catch {
            ForgeLog.log("[app] Failed to write session snapshot: \(error)")
        }
    }

    static func load(path: String) -> SessionSnapshot? {
        let url = fileURL(for: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(SessionSnapshot.self, from: data) else {
            ForgeLog.log("[app] Malformed session snapshot, deleting: \(url.lastPathComponent)")
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return snapshot
    }

    static func delete(path: String) {
        let url = fileURL(for: path)
        try? FileManager.default.removeItem(at: url)
    }

    private static func fileURL(for path: String) -> URL {
        let canonical = URL(fileURLWithPath: path).standardized.path
        let hash = SHA256.hash(data: Data(canonical.utf8))
        let hex = hash.prefix(16).map { String(format: "%02x", $0) }.joined()
        return sessionsDir.appendingPathComponent("\(hex).json")
    }
}
```

Uses first 16 bytes (32 hex chars) of SHA256 — sufficient uniqueness, shorter filenames.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Config/SessionSnapshotStore.swift
git commit -m "feat: add SessionSnapshotStore for snapshot file I/O"
```

---

### Task 4: TmuxAdapter — snapshot query methods

**Files:**
- Modify: `Sources/Infrastructure/Tmux/TmuxAdapter.swift`
- Modify: `Sources/Infrastructure/Tmux/TmuxStateParser.swift`

We need two new queries that return data for snapshot capture. These use `TmuxCommandRunner` (not control mode) so they can be awaited before `kill-session`.

- [ ] **Step 1: Add snapshot format strings and parsers to TmuxStateParser**

Add to `TmuxStateParser`:

```swift
// Snapshot capture formats
static let snapshotTabFormat = "#{window_index}\t#{window_name}\t#{window_layout}"
static let snapshotPaneFormat = "#{window_index}\t#{pane_index}\t#{pane_current_path}"

struct SnapshotTabInfo {
    let index: Int
    let name: String
    let layout: String
}

struct SnapshotPaneInfo {
    let windowIndex: Int
    let index: Int
    let directory: String
}

static func parseSnapshotTabs(_ output: String) -> [SnapshotTabInfo] {
    output.split(separator: "\n").compactMap { line in
        let p = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 3 else { return nil }
        return SnapshotTabInfo(index: Int(p[0]) ?? 0, name: p[1], layout: p[2])
    }
}

static func parseSnapshotPanes(_ output: String) -> [SnapshotPaneInfo] {
    output.split(separator: "\n").compactMap { line in
        let p = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard p.count >= 3 else { return nil }
        return SnapshotPaneInfo(windowIndex: Int(p[0]) ?? 0, index: Int(p[1]) ?? 0, directory: p[2])
    }
}
```

- [ ] **Step 2: Add `captureSessionSnapshot` to TmuxAdapter**

Add to `TmuxAdapter`:

```swift
func captureSessionSnapshot(project: String, path: String) async -> SessionSnapshot? {
    guard let tabOutput = await runner.run("list-windows", "-t", project, "-F", TmuxStateParser.snapshotTabFormat),
          let paneOutput = await runner.run("list-panes", "-s", "-t", project, "-F", TmuxStateParser.snapshotPaneFormat)
    else { return nil }

    let tabInfos = TmuxStateParser.parseSnapshotTabs(tabOutput)
    let paneInfos = TmuxStateParser.parseSnapshotPanes(paneOutput)
    let panesByWindow = Dictionary(grouping: paneInfos, by: \.windowIndex)

    let tabs = tabInfos.sorted(by: { $0.index < $1.index }).map { tab in
        let panes = (panesByWindow[tab.index] ?? []).sorted(by: { $0.index < $1.index }).map {
            PaneSnapshot(directory: $0.directory, index: $0.index)
        }
        let layout: String? = panes.count > 1 ? tab.layout : nil
        return TabSnapshot(name: tab.name, index: tab.index, layout: layout, panes: panes)
    }

    let canonical = URL(fileURLWithPath: path).standardized.path
    return SessionSnapshot(path: canonical, tabs: tabs)
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/Infrastructure/Tmux/TmuxAdapter.swift Sources/Infrastructure/Tmux/TmuxStateParser.swift
git commit -m "feat: add snapshot capture query to TmuxAdapter"
```

---

### Task 5: TmuxAdapter — restore command methods

**Files:**
- Modify: `Sources/Infrastructure/Tmux/TmuxAdapter.swift`

Add methods needed for restore. These use `runner.run` (awaited) so we can sequence them deterministically.

- [ ] **Step 1: Add restore methods to TmuxAdapter**

```swift
func restoreTab(session: String, name: String, directory: String) async -> String? {
    await runner.run("new-window", "-P", "-F", "#{window_id}", "-t", "\(session):", "-n", name, "-c", directory)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func restoreSplit(targetPane: String, direction: SplitDirection) async -> String? {
    let flag = direction == .horizontal ? "-h" : "-v"
    return await runner.run("split-window", flag, "-P", "-F", "#{pane_id}", "-t", targetPane)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func applyLayout(windowId: String, layout: String) async {
    _ = await runner.run("select-layout", "-t", windowId, layout)
}

func sendKeys(paneId: String, keys: String) async {
    _ = await runner.run("send-keys", "-t", paneId, keys, "Enter")
}

func renameWindow(target: String, name: String) async {
    _ = await runner.run("rename-window", "-t", target, name)
}

func listPaneIds(window: String) async -> [String] {
    guard let output = await runner.run("list-panes", "-t", window, "-F", "#{pane_id}") else { return [] }
    return output.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "\n").map(String.init)
}
```

Note: `restoreSplit` differs from existing `splitWindow` — it uses `runner.run` (awaited, returns new pane ID) instead of `controlMode.send` (fire-and-forget). `renameWindow` and `listPaneIds` are also awaited (not control mode) for deterministic sequencing during restore.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/Infrastructure/Tmux/TmuxAdapter.swift
git commit -m "feat: add restore methods to TmuxAdapter"
```

---

### Task 6: Capture flow — snapshot on project close

**Files:**
- Modify: `Sources/WorkspaceController+Actions.swift`
- Modify: `Sources/Features/CommandPalette/CommandRegistry.swift`
- Modify: `Sources/MenuCommands.swift`
- Modify: `Sources/Features/Sidebar/SidebarProjectList.swift`
- Modify: `Sources/Infrastructure/Debug/DebugServer+Responses.swift`

`removeProject` becomes `async` to await the snapshot capture before kill. All call sites wrap in `Task { await ... }`.

- [ ] **Step 1: Make `removeProject` async with snapshot capture**

In `WorkspaceController+Actions.swift`, replace `removeProject`:

```swift
func removeProject(_ project: Project) async {
    ForgeLog.log("[app] Removing project: \(project.name)")
    // Killing any session may disconnect control mode (if it's attached to
    // that session). Set the flag so onDisconnect suppresses the toast.
    expectingDisconnect = true

    // Snapshot tab layout before kill — path is needed for lookup key
    if let path = project.path {
        if let snapshot = await (tmux as? TmuxAdapter)?.captureSessionSnapshot(project: project.name, path: path) {
            SessionSnapshotStore.save(snapshot)
        }
    }

    if let index = workspace.projects.firstIndex(where: { $0.id == project.id }) {
        let nextIndex = index > 0 ? index - 1 : min(1, workspace.projects.count - 1)
        if nextIndex != index {
            selectProject(workspace.projects[nextIndex])
        }
    }
    Task { await tmux.killProject(name: project.name) }
}
```

Note: `captureSessionSnapshot` is on `TmuxAdapter` (not the protocol) since it's a composite query used only here. The cast `(tmux as? TmuxAdapter)` keeps it simple without adding to the port protocol. If the cast fails (e.g., in tests with a mock), snapshot capture is skipped gracefully.

- [ ] **Step 2: Update call sites to wrap in Task**

In `closeCurrentPane()` (same file):
```swift
case .project(let project):
    Task { await removeProject(project) }
```

In `CommandRegistry.swift`:
```swift
Task { await controller.removeProject(project) }
```

In `MenuCommands.swift`:
```swift
Task { await controller.removeProject(project) }
```

In `SidebarProjectList.swift`:
```swift
Button("Close Project", role: .destructive) { Task { await controller.removeProject(project) } }
```

In `DebugServer+Responses.swift`:
```swift
await ctrl.removeProject(project)
```
(Already inside an async context.)

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Test**

Run: `swift test 2>&1 | tail -5`
Expected: All existing tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/WorkspaceController+Actions.swift Sources/Features/CommandPalette/CommandRegistry.swift Sources/MenuCommands.swift Sources/Features/Sidebar/SidebarProjectList.swift Sources/Infrastructure/Debug/DebugServer+Responses.swift
git commit -m "feat: snapshot tab layout on project close"
```

---

### Task 7: Restore flow — rebuild layout on project open

**Files:**
- Modify: `Sources/WorkspaceController+Actions.swift`

- [ ] **Step 1: Add restore logic to `addProject`**

Add a private restore method and call it from `addProject`:

```swift
func addProject(name: String, path: String) async {
    let success = await tmux.newProject(name: name, path: path)
    guard success else {
        toastState.show(
            title: "Failed to create project",
            message: "Could not create tmux session \"\(name)\"",
            icon: "exclamationmark.triangle.fill"
        )
        return
    }
    if expectingDisconnect {
        expectingDisconnect = false
        startControlMode()
    }

    // Restore saved tab layout if available
    if let adapter = tmux as? TmuxAdapter {
        await restoreSession(name: name, path: path, adapter: adapter)
    }

    await syncEngine.refresh()
    if let project = workspace.projects.first(where: { $0.name == name }) {
        selectProject(project)
    }
}

private func restoreSession(name: String, path: String, adapter: TmuxAdapter) async {
    let canonical = URL(fileURLWithPath: path).standardized.path
    guard let snapshot = SessionSnapshotStore.load(path: canonical),
          !snapshot.tabs.isEmpty else { return }

    ForgeLog.log("[app] Restoring \(snapshot.tabs.count) tabs for \(name)")

    for (i, tab) in snapshot.tabs.enumerated() {
        let windowTarget: String
        if i == 0 {
            // Tab 0 already exists from new-session — rename via runner (not control mode)
            await adapter.renameWindow(target: "\(name):0", name: tab.name)
            windowTarget = "\(name):0"
        } else {
            let firstDir = tab.panes.first?.directory ?? path
            guard let windowId = await adapter.restoreTab(session: name, name: tab.name, directory: firstDir) else {
                ForgeLog.log("[app] Failed to restore tab \(tab.name)")
                continue
            }
            windowTarget = windowId
        }

        // Restore pane splits
        if tab.panes.count > 1, let layout = tab.layout {
            let tree = LayoutParser.parse(layout)
            let existingPaneIds = await adapter.listPaneIds(window: windowTarget)
            guard let firstPaneId = existingPaneIds.first else { continue }

            // Walk the tree, creating splits and collecting leaf pane IDs in order
            var leafPaneIds: [String] = []
            await collectLeafPanes(tree: tree, adapter: adapter, currentPaneId: firstPaneId, leafPaneIds: &leafPaneIds)

            // Apply saved layout for exact proportions
            await adapter.applyLayout(windowId: windowTarget, layout: layout)

            // Send cd to each pane
            for (j, pane) in tab.panes.enumerated() where j < leafPaneIds.count {
                if pane.directory != path {
                    await adapter.sendKeys(paneId: leafPaneIds[j], keys: "cd \(shellQuote(pane.directory))")
                }
            }
        } else if let pane = tab.panes.first, i == 0, pane.directory != path {
            // Single-pane tab 0: cd if directory differs
            if let paneId = (await adapter.listPaneIds(window: windowTarget)).first {
                await adapter.sendKeys(paneId: paneId, keys: "cd \(shellQuote(pane.directory))")
            }
        }
    }

    SessionSnapshotStore.delete(path: canonical)
    ForgeLog.log("[app] Restored session snapshot for \(name)")
}

/// Walk the split tree depth-first, creating panes and collecting leaf IDs in order.
/// For a leaf node: append the current pane ID.
/// For a split node: split the current pane N-1 times, then recurse into each child.
private func collectLeafPanes(
    tree: SplitNode, adapter: TmuxAdapter,
    currentPaneId: String, leafPaneIds: inout [String]
) async {
    switch tree {
    case .leaf:
        leafPaneIds.append(currentPaneId)
    case .split(let direction, let children):
        // First child inherits currentPaneId, subsequent children get new panes
        var childPaneIds = [currentPaneId]
        for _ in children.dropFirst() {
            if let newId = await adapter.restoreSplit(targetPane: currentPaneId, direction: direction) {
                childPaneIds.append(newId)
            }
        }
        // Recurse into each child
        for (i, child) in children.enumerated() where i < childPaneIds.count {
            await collectLeafPanes(tree: child, adapter: adapter, currentPaneId: childPaneIds[i], leafPaneIds: &leafPaneIds)
        }
    }
}

private func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
```

Note: `collectLeafPanes` is the core of the multi-pane restore. It walks the `SplitNode` tree depth-first. Leaf nodes append their pane ID. Split nodes create N-1 new panes via `restoreSplit`, then recurse into each child. This guarantees leaf N in the tree walk maps to saved pane N.

All tmux calls during restore go through dedicated `TmuxAdapter` methods (`listPaneIds`, `renameWindow`, `restoreSplit`, etc.) — never through `runner` directly.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build succeeds

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/WorkspaceController+Actions.swift Sources/Infrastructure/Tmux/TmuxAdapter.swift
git commit -m "feat: restore tab layout on project open"
```

---

### Task 8: Manual verification

- [ ] **Step 1: Build and launch**

Run: `make dev`

- [ ] **Step 2: Create a multi-tab project**

1. Open a project (e.g., `~/Personal/forge`)
2. Add 2-3 tabs, rename some
3. Split a pane in one tab
4. `cd` into different directories in different panes

- [ ] **Step 3: Close and reopen**

1. Close the project (Cmd+Shift+W)
2. Verify snapshot file exists: `ls ~/.config/forge/sessions/`
3. Reopen the same folder
4. Verify: tabs restored with correct names, splits recreated, directories correct

- [ ] **Step 4: Verify screenshot**

```bash
curl localhost:7654/screenshot > /tmp/forge-screenshot.png
```
Read the screenshot to visually confirm tabs are restored.

- [ ] **Step 5: Check logs for errors**

```bash
tail -30 /tmp/forge.log | grep -i "snapshot\|restore"
```

- [ ] **Step 6: Verify snapshot deleted after restore**

```bash
ls ~/.config/forge/sessions/
```
The snapshot file should be gone after successful restore.
