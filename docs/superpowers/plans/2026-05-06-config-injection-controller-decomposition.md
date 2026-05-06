# Config Injection + Controller Decomposition

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate ForgeConfigStore.shared singleton from all consumers and decompose WorkspaceController into focused modules, establishing patterns for 10x codebase growth.

**Architecture:** ForgeConfigStore becomes an injected dependency everywhere — via `@Environment` in SwiftUI views, via constructor in non-view types. WorkspaceController sheds refresh/sync, content scanning, and UI persistence into dedicated types (TmuxSyncEngine, expanded AttentionManager, UIStatePersistence), becoming a thin command router.

**Tech Stack:** Swift 6.0, SwiftUI, macOS 14+

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `Sources/Infrastructure/Tmux/TmuxSyncEngine.swift` | Owns the refresh cycle: query tmux, merge state via StateMerger, run post-refresh hooks, manage debounce/polling timers. ~150 lines. |
| `Sources/Infrastructure/Config/UIStatePersistence.swift` | Save/restore active project+tab selection, sidebar state, recent directories. ~80 lines. |

### Modified Files (significant changes)
| File | Change |
|------|--------|
| `Sources/WorkspaceController.swift` | Shed refresh, content scan, UI persistence. Add injected config. ~200 lines after. |
| `Sources/Features/Attention/AttentionManager.swift` | Absorb ContentDetector + content scanning loop. Expose `scanAfterRefresh()` hook. |
| `Sources/ForgeApp.swift` | Wire new types in AppDelegate. Inject config into environment. |
| `Sources/Features/TitleBar/TitleBarManager.swift` | Replace `.shared` with injected config store. |
| `Sources/MenuCommands.swift` | Take config store parameter for stack mode checks. |

### Modified Files (mechanical .shared → injected replacement)
All views that reference `ForgeConfigStore.shared` — ~15 files. Each adds `@Environment(ForgeConfigStore.self) private var configStore` and replaces `.shared` references.

---

## Phase 1: Inject ForgeConfigStore

### Task 1: Constructor-inject config into non-view types

**Files:**
- Modify: `Sources/WorkspaceController.swift`
- Modify: `Sources/Features/TitleBar/TitleBarManager.swift`
- Modify: `Sources/Features/Attention/AttentionManager.swift`
- Modify: `Sources/ForgeApp.swift`

- [ ] **Step 1:** Add `let config: ForgeConfigStore` property to WorkspaceController. Add it to init parameters. Update the 6 `.shared` references inside WorkspaceController to use `self.config`.

- [ ] **Step 2:** Update AppDelegate to pass config store: `WorkspaceController(tmux: TmuxAdapter(), git: GitAdapter(), config: ForgeConfigStore.shared)`.

- [ ] **Step 3:** TitleBarManager already takes constructor params. Add `config: ForgeConfigStore`, replace all 12 `.shared` references with `self.config`. Update AppDelegate call site.

- [ ] **Step 4:** AttentionManager already takes `config: ForgeConfigStore`. Verify it's not also using `.shared` internally. If so, replace.

- [ ] **Step 5:** `swift build && swift test` — verify.

- [ ] **Step 6:** Commit: `refactor: constructor-inject ForgeConfigStore into non-view types`

### Task 2: Environment-inject config into SwiftUI views

**Files:**
- Modify: `Sources/ForgeApp.swift` (add `.environment`)
- Modify: ~15 view files

- [ ] **Step 1:** In AppDelegate.createMainWindow(), add `.environment(ForgeConfigStore.shared)` to the root view alongside the existing `.environment(controller)` and `.environment(attentionManager!)`.

- [ ] **Step 2:** Update each view file that references `ForgeConfigStore.shared`:
  - Add `@Environment(ForgeConfigStore.self) private var configStore`
  - Replace `ForgeConfigStore.shared` with `configStore`
  - Files: MainView, ProjectDetailView, WindowTabBar, SidebarProjectList, StackView, StackToolbar, StackEmptyState, ForgeTerminalView, ProjectRow, NotificationCenterRow, ProjectPickerView

- [ ] **Step 3:** `swift build` — verify.

- [ ] **Step 4:** Commit: `refactor: environment-inject ForgeConfigStore into all views`

### Task 3: Fix remaining static references

**Files:**
- Modify: `Sources/Features/Shared/KeyboardShortcuts.swift`
- Modify: `Sources/MenuCommands.swift`

- [ ] **Step 1:** KeyboardShortcuts — the static `resolve()` method reads `.shared`. Change it to accept a `ForgeConfigStore` parameter. Update all call sites (views that resolve shortcuts already have configStore in environment).

- [ ] **Step 2:** MenuCommands — reads `.shared.isStackMode` to conditionally show menu items. Add `let config: ForgeConfigStore` property. Update AppDelegate call site.

- [ ] **Step 3:** `swift build && swift test` — verify.

- [ ] **Step 4:** Grep for `ForgeConfigStore.shared` in Sources/. The ONLY remaining reference should be in `ForgeConfigStore.swift` itself (the static property definition) and `AppDelegate` (the composition root). Any others → fix.

- [ ] **Step 5:** Commit: `refactor: eliminate all ForgeConfigStore.shared references outside composition root`

---

## Phase 2: Extract TmuxSyncEngine

### Task 4: Create TmuxSyncEngine

**Files:**
- Create: `Sources/Infrastructure/Tmux/TmuxSyncEngine.swift`

- [ ] **Step 1:** Create `TmuxSyncEngine` class:

```swift
@MainActor
final class TmuxSyncEngine {
    private let workspace: Workspace
    private let tmux: any TmuxPort
    private let git: any GitPort
    private let config: ForgeConfigStore
    private var onPostRefresh: (() async -> Void)?

    private var refreshTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var isRefreshing = false
    private var needsRefreshAfterCurrent = false
    private var lastGitBranchProjectId: String?
    private(set) var gitBranch: String?

    init(workspace: Workspace, tmux: any TmuxPort, git: any GitPort, config: ForgeConfigStore)

    func start()           // begins periodic refresh + control mode
    func stop()            // cancels timers
    func scheduleRefresh() // debounced refresh (called by event handler)
    func refresh() async   // full sync cycle
    func setPostRefreshHook(_ hook: @escaping () async -> Void)
}
```

- [ ] **Step 2:** Move these methods from WorkspaceController into TmuxSyncEngine:
  - `refresh()` (but remove the content detection loop — that becomes the hook)
  - `scheduleRefresh()`
  - `startPeriodicRefresh()`
  - `mergeProjectState()`
  - `mergeTabState()`
  - `mergePaneState()`
  - `fetchGitBranch()`

- [ ] **Step 3:** At the end of `refresh()`, call `await onPostRefresh?()` — this is where AttentionManager will plug in content scanning.

- [ ] **Step 4:** Move `gitBranch` property to TmuxSyncEngine (it's a refresh output, not a controller concern).

- [ ] **Step 5:** `swift build` — will fail because WorkspaceController still references removed methods. That's expected — Task 5 wires it up.

### Task 5: Wire TmuxSyncEngine into WorkspaceController

**Files:**
- Modify: `Sources/WorkspaceController.swift`
- Modify: `Sources/ForgeApp.swift`
- Modify: `Sources/Features/TitleBar/TitleBarManager.swift`

- [ ] **Step 1:** Add `let syncEngine: TmuxSyncEngine` property to WorkspaceController. Remove the moved methods, moved stored properties (`refreshTask`, `refreshDebounceTask`, `isRefreshing`, `needsRefreshAfterCurrent`, `lastGitBranchProjectId`, `gitBranch`).

- [ ] **Step 2:** Update `connect()`:
  - Replace `await refresh()` with `await syncEngine.refresh()`
  - Replace `startPeriodicRefresh()` with `syncEngine.start()` (which starts periodic refresh internally)
  - Replace `tmux.startControlMode { ... }` — keep it here but have the event handler call `syncEngine.scheduleRefresh()` instead of `self.scheduleRefresh()`

- [ ] **Step 3:** Update `disconnect()`:
  - Replace `refreshTask?.cancel()` with `syncEngine.stop()`

- [ ] **Step 4:** Update `handleEvent()`:
  - Replace `scheduleRefresh()` calls with `syncEngine.scheduleRefresh()`

- [ ] **Step 5:** Update `gitBranch` references — WorkspaceController.gitBranch becomes a computed property: `var gitBranch: String? { syncEngine.gitBranch }`.

- [ ] **Step 6:** In AppDelegate, create TmuxSyncEngine and inject into WorkspaceController. Update TitleBarManager to read gitBranch from controller (which delegates to syncEngine) — no change needed there since it already reads `controller.gitBranch`.

- [ ] **Step 7:** `swift build && swift test` — verify.

- [ ] **Step 8:** Commit: `refactor: extract TmuxSyncEngine from WorkspaceController`

---

## Phase 3: Move Content Scanning to Attention Feature

### Task 6: Expand AttentionManager with content scanning

**Files:**
- Modify: `Sources/Features/Attention/AttentionManager.swift`
- Modify: `Sources/Infrastructure/Tmux/TmuxSyncEngine.swift`
- Modify: `Sources/WorkspaceController.swift`

- [ ] **Step 1:** Move `ContentDetector` ownership from WorkspaceController to AttentionManager. Add `let contentDetector = ContentDetector()` property.

- [ ] **Step 2:** Add `scanForContentMatches(workspace:tmux:)` method to AttentionManager. This is the content detection loop currently at WorkspaceController lines 78-101, adapted to use `self.config` instead of `ForgeConfigStore.shared`:

```swift
func scanForContentMatches(workspace: Workspace, tmux: any TmuxPort) async {
    let patterns = ContentDetector.defaultPatterns
        + (config.config.stackView?.contentPatterns ?? [])
    for project in workspace.projects {
        for tab in project.tabs {
            for pane in tab.panes where pane.status == .running {
                if let content = await tmux.capturePaneContent(id: pane.id, lastN: pane.height) {
                    let isNewMatch = contentDetector.scan(paneId: pane.id, content: content, patterns: patterns)
                    if isNewMatch {
                        ForgeLog.log("[attention] Content match in pane \(pane.id): \(content.suffix(80))")
                        pane.hasContentMatch = true
                        handleEvent(.contentMatch(tabUUID: tab.uuid))
                    }
                }
            }
            for pane in tab.panes where pane.hasContentMatch {
                if !contentDetector.isActive(paneId: pane.id) {
                    pane.hasContentMatch = false
                }
            }
        }
    }
}
```

- [ ] **Step 3:** Remove `contentDetector` property and content detection loop from WorkspaceController.

- [ ] **Step 4:** In AppDelegate, register the post-refresh hook:
```swift
syncEngine.setPostRefreshHook { [weak self] in
    guard let self else { return }
    await self.attentionManager.scanForContentMatches(
        workspace: self.controller.workspace, tmux: tmuxAdapter
    )
}
```
Note: AppDelegate needs to keep a reference to the tmux adapter for the hook. Store `let tmuxAdapter = TmuxAdapter()` as a property.

- [ ] **Step 5:** `swift build && swift test` — verify.

- [ ] **Step 6:** Commit: `refactor: move content scanning into Attention feature`

---

## Phase 4: Extract UIStatePersistence

### Task 7: Create UIStatePersistence

**Files:**
- Create: `Sources/Infrastructure/Config/UIStatePersistence.swift`
- Modify: `Sources/WorkspaceController.swift`
- Modify: `Sources/ForgeApp.swift`

- [ ] **Step 1:** Create UIStatePersistence:

```swift
@MainActor
final class UIStatePersistence {
    private let config: ForgeConfigStore

    init(config: ForgeConfigStore) { self.config = config }

    func save(workspace: Workspace, sidebarVisible: Bool? = nil, expandedProjectNames: [String]? = nil) {
        // Move saveUIState() logic here
    }

    func restore(workspace: Workspace, tmux: any TmuxPort) {
        // Move restoreUIState() logic here
    }

    func seedRecentDirectories(from workspace: Workspace) {
        // Move seedRecentDirectories() logic here
    }
}
```

- [ ] **Step 2:** Move the three methods from WorkspaceController, adapting them to take workspace as a parameter.

- [ ] **Step 3:** Add `let uiState: UIStatePersistence` to WorkspaceController. Inject via constructor. Replace internal calls:
  - `saveUIState(...)` → `uiState.save(workspace: workspace, ...)`
  - `restoreUIState()` → `uiState.restore(workspace: workspace, tmux: tmux)`
  - `seedRecentDirectories()` → `uiState.seedRecentDirectories(from: workspace)`

- [ ] **Step 4:** Update AppDelegate to create UIStatePersistence and pass to WorkspaceController.

- [ ] **Step 5:** `swift build && swift test` — verify.

- [ ] **Step 6:** Commit: `refactor: extract UIStatePersistence from WorkspaceController`

---

## Phase 5: Verify and Document

### Task 8: Verify line counts and architecture

- [ ] **Step 1:** Check all new/modified files are under 300 lines:
  - `wc -l Sources/WorkspaceController.swift` — target ~200
  - `wc -l Sources/Infrastructure/Tmux/TmuxSyncEngine.swift` — target ~150
  - `wc -l Sources/Features/Attention/AttentionManager.swift` — target ~150
  - `wc -l Sources/Infrastructure/Config/UIStatePersistence.swift` — target ~80

- [ ] **Step 2:** Grep for `ForgeConfigStore.shared` — only in `ForgeConfigStore.swift` (definition) and `AppDelegate` (composition root).

- [ ] **Step 3:** `swift build && swift test` — final verification, all 52 tests pass.

### Task 9: Update CLAUDE.md and docs

**Files:**
- Modify: `CLAUDE.md`
- Modify: `CONTEXT.md`

- [ ] **Step 1:** Update CLAUDE.md architecture diagram to show TmuxSyncEngine, UIStatePersistence, and the expanded AttentionManager.

- [ ] **Step 2:** Add to CONTEXT.md:
  - **TmuxSyncEngine** — definition
  - **UIStatePersistence** — definition
  - **Post-refresh hook** — the pattern for features to participate in the sync cycle

- [ ] **Step 3:** Commit: `docs: update architecture for controller decomposition`

---

## Verification

After all tasks:
1. `swift build` succeeds
2. `swift test` — all 52 tests pass
3. `grep -r 'ForgeConfigStore\.shared' Sources/ | grep -v 'ForgeConfigStore.swift' | grep -v 'ForgeApp.swift'` — returns nothing
4. `wc -l Sources/WorkspaceController.swift` — under 250
5. `make dev` + `curl localhost:7654/screenshot` — visual sanity check
