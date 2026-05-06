# Stack Mode Design

## Context

Forge currently operates in "list mode" — a sidebar of projects with expandable tabs, plus a terminal area. Stack mode is a new alternative UI mode for triaging terminals that need attention. When multiple AI coding tools (Claude Code, Codex, aider) or background tasks complete across different projects, stack mode surfaces them one at a time in a full-screen terminal with simple triage actions: done, hide, or move to back.

The `isStackMode` toggle already exists in `ForgeConfigStore` with `Cmd+Shift+M` binding, but currently has no effect on the UI. A stub `StackModeSettingsPane.swift` also exists in the settings views.

## Architecture

DDD layered architecture matching existing patterns:

```
Domain (pure Swift, no frameworks)
├── AttentionQueue       — value type, queue operations
├── AttentionEvent       — enum (bell, commandCompleted) with windowUUID computed property
├── AttentionPort        — protocol for attention system
└── NotificationPort     — Sendable protocol for native notifications

Application (@Observable, coordinates domain + side effects)
└── AttentionManager     — implements AttentionPort, owns queue + hiddenSet (single source of truth)

Adapters (infrastructure)
└── MacNotificationAdapter — implements NotificationPort via UNUserNotificationCenter

Views (SwiftUI)
├── StackView            — full-screen stack mode container
├── StackToolbar         — action bar with project/tab info + buttons
└── StackEmptyState      — empty queue state
```

## Detection Strategy

Hybrid — two complementary signals:

1. **Bell events** (`%bell` from tmux control mode): Primary signal for AI tools. Instant. Claude Code, Codex, and most modern tools ring the terminal bell on completion.
2. **Command completion** (`pane_current_command` transition from non-shell to shell): Catches regular terminal commands finishing. Detected on existing 5-second refresh cycle.

Both fire `AttentionEvent` into `AttentionManager`.

## Domain Layer

### AttentionQueue (`Sources/Domain/Models/AttentionQueue.swift`)

Pure value type. No framework dependencies.

```swift
struct AttentionQueue {
    private var items: [UUID] = []

    mutating func enqueue(_ id: UUID)          // add to back, no-op if present
    mutating func dequeue() -> UUID?           // remove and return front
    mutating func insertAtFront(_ id: UUID)    // add to front, no-op if present
    mutating func moveToBack(_ id: UUID)       // remove from position, add to back
    mutating func remove(_ id: UUID)           // remove entirely
    func peek() -> UUID?                       // front without removing
    func contains(_ id: UUID) -> Bool
    var isEmpty: Bool
    var count: Int
}
```

### AttentionEvent (`Sources/Domain/Models/AttentionEvent.swift`)

```swift
enum AttentionEvent {
    case bell(windowUUID: UUID)
    case commandCompleted(windowUUID: UUID)

    var windowUUID: UUID {
        switch self {
        case .bell(let id), .commandCompleted(let id): return id
        }
    }
}
```

### AttentionPort (`Sources/Domain/Ports/AttentionPort.swift`)

```swift
@MainActor
protocol AttentionPort: AnyObject {
    func handleEvent(_ event: AttentionEvent)
    func markDone(_ windowUUID: UUID)
    func hide(_ windowUUID: UUID)
    func moveToBack(_ windowUUID: UUID)
    func unhide(_ windowUUID: UUID)
    func removeWindow(_ windowUUID: UUID)
    var currentWindowUUID: UUID? { get }
    var queueCount: Int { get }
    func needsAttention(_ windowUUID: UUID) -> Bool
    func isHidden(_ windowUUID: UUID) -> Bool
}
```

### NotificationPort (`Sources/Domain/Ports/NotificationPort.swift`)

```swift
protocol NotificationPort: Sendable {
    func requestPermission() async -> Bool
    func send(title: String, body: String, sound: String?) async
}
```

### Window Model Changes (`Sources/Domain/Models/Window.swift`)

- Add `uuid: UUID = UUID()` — generated on init, stable for window lifetime
- UUID survives `mergeWindowState` because merging matches by tmux `id` (String) and updates existing Window objects in-place — the UUID is never reassigned after init
- No `hiddenFromStack` property on Window — hidden state lives exclusively in `AttentionManager.hiddenSet` (single source of truth)
- **Cross-restart behavior**: UUIDs are regenerated on app restart (new Window objects). `hiddenWindowUUIDs` in config become stale. `AttentionManager.init()` prunes stale UUIDs by checking them against the current workspace windows after initial tmux sync. This is acceptable because hide is a triage action, not a permanent config — after restart, all windows start fresh.

### Pane Model Changes (`Sources/Domain/Models/Pane.swift`)

- Add `previousCommand: String = ""` — tracks last known `currentCommand` for detecting transitions
- Used by `WorkspaceController.mergePaneState()` to detect command completion (non-shell → shell)
- Shell detection reuses existing `PaneStatus.from(command:)` which checks for `zsh`, `bash`, `fish` (extend to include `sh`, `nu`, `pwsh`)

## Application Layer

### AttentionManager (`Sources/App/AttentionManager.swift`)

```swift
@Observable @MainActor
final class AttentionManager: AttentionPort {
    private var queue = AttentionQueue()
    private(set) var hiddenSet: Set<UUID> = []   // single source of truth, persisted to config
    private let notifier: any NotificationPort
    private let config: ForgeConfigStore

    var currentWindowUUID: UUID? { queue.peek() }
    var queueCount: Int { queue.count }

    init(notifier: any NotificationPort, config: ForgeConfigStore) {
        self.notifier = notifier
        self.config = config
        self.hiddenSet = loadHiddenSet(from: config)  // rehydrate on startup
    }

    /// Call after initial tmux sync to prune stale UUIDs from a previous session
    func pruneStaleHiddenEntries(validUUIDs: Set<UUID>) {
        let stale = hiddenSet.subtracting(validUUIDs)
        if !stale.isEmpty {
            hiddenSet.subtract(stale)
            persistHiddenSet()
        }
    }

    func handleEvent(_ event: AttentionEvent) {
        let uuid = event.windowUUID
        guard !hiddenSet.contains(uuid) else { return }
        queue.enqueue(uuid)

        let settings = config.config.stackView
        if settings?.notify == "always" {
            Task { await notifier.send(title: "...", body: "...", sound: settings?.notificationSound) }
        }
        if settings?.bringToForeground == "always" {
            NSApp.activate()
        }
    }

    func markDone(_ windowUUID: UUID) {
        queue.remove(windowUUID)         // remove specific window, not blind dequeue
        // Caller (StackView) also clears hasBell on the window's panes
    }

    func hide(_ windowUUID: UUID) {
        queue.remove(windowUUID)
        hiddenSet.insert(windowUUID)
        persistHiddenSet()
    }

    func moveToBack(_ windowUUID: UUID) {
        queue.moveToBack(windowUUID)
    }

    func unhide(_ windowUUID: UUID) {
        hiddenSet.remove(windowUUID)
        persistHiddenSet()
    }

    func removeWindow(_ windowUUID: UUID) {
        queue.remove(windowUUID)
        hiddenSet.remove(windowUUID)
    }

    func needsAttention(_ windowUUID: UUID) -> Bool {
        queue.contains(windowUUID)
    }

    func isHidden(_ windowUUID: UUID) -> Bool {
        hiddenSet.contains(windowUUID)
    }

    func promoteToFront(_ windowUUID: UUID) {
        queue.remove(windowUUID)
        queue.insertAtFront(windowUUID)
    }

    private func persistHiddenSet() {
        config.update { config in
            config.stackView = config.stackView ?? StackViewSettings()
            config.stackView?.hiddenWindowUUIDs = hiddenSet.map(\.uuidString)
        }
    }

    private func loadHiddenSet(from config: ForgeConfigStore) -> Set<UUID> {
        Set((config.config.stackView?.hiddenWindowUUIDs ?? []).compactMap(UUID.init))
    }
}
```

Injected via `@Environment` alongside `WorkspaceController`.

### WorkspaceController Integration

**Bell handling** in `handleEvent()` — runs synchronously before `scheduleRefresh()`:
```swift
if event.hasPrefix("%bell") {
    // existing: set pane.hasBell = true (inline loop by tmux window ID)
    // new: reuse that same loop to get the Window object, then:
    attentionManager.handleEvent(.bell(windowUUID: window.uuid))
    return  // early return, no refresh needed (same as existing behavior)
}
```

**Command completion** in `mergePaneState()` — save `previousCommand` BEFORE updating `currentCommand`:
```swift
// In the existing merge loop, BEFORE `existing.currentCommand = info.currentCommand`:
let wasRunning = PaneStatus.from(command: existing.currentCommand) == .running
let nowIdle = PaneStatus.from(command: info.currentCommand) == .idle
if wasRunning && nowIdle {
    attentionManager.handleEvent(.commandCompleted(windowUUID: window.uuid))
}
existing.previousCommand = existing.currentCommand  // save before overwrite
existing.currentCommand = info.currentCommand       // existing line
```

**Window destruction** — runs synchronously in `handleEvent()` before `scheduleRefresh()` debounce:
```swift
if event.hasPrefix("%window-close") || event.hasPrefix("%unlinked-window-close") {
    // Parse window ID from event, look up window in workspace sessions
    // This runs synchronously before scheduleRefresh()'s 150ms debounce,
    // so the Window object is still in the sessions array
    if let window = workspace.findWindow(byTmuxId: closedWindowId)?.window {
        attentionManager.removeWindow(window.uuid)
    }
    scheduleRefresh()
    return
}
```

### Window Lookup Helpers

Add to `Workspace`:
```swift
func findWindow(byUUID uuid: UUID) -> (session: Session, window: Window)? {
    for session in sessions {
        if let window = session.windows.first(where: { $0.uuid == uuid }) {
            return (session, window)
        }
    }
    return nil
}

func findWindow(byTmuxId tmuxId: String) -> (session: Session, window: Window)? {
    for session in sessions {
        if let window = session.windows.first(where: { $0.id == tmuxId }) {
            return (session, window)
        }
    }
    return nil
}
```

## Adapters

### MacNotificationAdapter (`Sources/Adapters/Notification/MacNotificationAdapter.swift`)

Implements `NotificationPort` (marked `Sendable`). Wraps `UNUserNotificationCenter`.

- `requestPermission()`: Requests notification authorization (.alert, .sound)
- `send()`: Creates `UNMutableNotificationContent` with title, body, and sound
  - System sounds: `UNNotificationSound(named: ...)`
  - Custom .aiff/.wav: `UNNotificationSound(named: ...)` with file copied to app's notification sounds directory

## Views

### StackView (`Sources/App/Views/Stack/StackView.swift`)

Full-screen container. No sidebar.

```
┌──────────────────────────────────────────┐
│ Title bar (unchanged — path + branch)    │
├──────────────────────────────────────────┤
│                                          │
│          TerminalArea                    │
│    (all panes visible, keyboard focus    │
│     on attention-triggering pane)         │
│                                          │
├──────────────────────────────────────────┤
│ StackToolbar (bottom default, top opt.)  │
└──────────────────────────────────────────┘
```

- When queue is empty: toolbar hidden, `StackEmptyState` shown instead of terminal
- Toolbar position controlled by separate `stackViewToolbarPosition` setting
- If `currentWindowUUID` maps to a window that no longer exists (race condition), call `attentionManager.removeWindow()` and show next

### StackToolbar (`Sources/App/Views/Stack/StackToolbar.swift`)

Single row. Button placement follows `sidebarPosition` setting — buttons go on the same side as the sidebar would be in list mode. This keeps navigation controls on the side the user's eye is trained to look for them, even though the sidebar isn't visible.

- Sidebar right: `[project] --- [tab] [Done] [Hide] [Move to Back]`
- Sidebar left: `[Done] [Hide] [Move to Back] [project] --- [tab]`

3 action buttons:
- **Done** (checkmark icon `checkmark`, tooltip "Done"): `Cmd+Return`
- **Hide** (eye-slash icon `eye.slash`, tooltip "Hide"): `Cmd+Shift+H`
- **Move to Back** (arrow-to-line icon `arrow.right.to.line`, tooltip "Move to Back"): `Cmd+Shift+]`

### StackEmptyState (`Sources/App/Views/Stack/StackEmptyState.swift`)

Centered vertically, no toolbar:
- Checkmark icon (large, dimmed)
- "Nothing needs your attention"
- "Terminals will appear here when they need input"
- "Switch to List View" link → toggles `isStackMode = false`

### MainView Changes

```swift
if store.isStackMode {
    StackView()
} else {
    // existing sidebar + detail layout
}
```

### List Mode Context Menu Additions

In `WindowTabBar.swift` tab context menu and `SidebarTabRow` context menu:
- "Hide from Stack View" (when `attentionManager.isHidden(window.uuid) == false`)
- "Unhide from Stack View" (when `attentionManager.isHidden(window.uuid) == true`)

## Mode Switching

**List to Stack (`Cmd+Shift+M`):**
1. If current window needs attention → `attentionManager.promoteToFront(window.uuid)`
2. Set `isStackMode = true`
3. No double-repaint: `promoteToFront()` fires before `isStackMode` flips, and `StackView` doesn't exist in the view hierarchy until step 2 — so the queue mutation is invisible and only one render occurs

**Stack to List:**
1. Set `isStackMode = false`
2. The window currently shown in stack becomes the selected window in list mode (set `activeSessionId` and `activeWindowId`)

## Settings

### Expand Existing Stub (`Sources/App/Views/Settings/StackModeSettingsPane.swift`)

Icon: `rectangle.stack` (matching existing `SettingsView.swift`)

| Setting | Type | Default |
|---------|------|---------|
| Toolbar Position | `top` / `bottom` dropdown | `bottom` |
| Bring to Foreground | `never` / `always` dropdown | `never` |
| Notify | `always` / `never` dropdown | `never` |
| Notification Sound | system sounds picker + "Custom..." with file picker | system default |
| Test Notification | button | — |

### Config Changes (`Sources/Adapters/Config/ForgeConfig.swift`)

```swift
struct StackViewSettings: Codable, Equatable {
    var toolbarPosition: String?        // "top" or "bottom"
    var bringToForeground: String?      // "never" or "always"
    var notify: String?                 // "always" or "never"
    var notificationSound: String?      // system sound name or custom file path
    var hiddenWindowUUIDs: [String]?    // persisted hidden set (ephemeral across restarts, pruned on sync)
}
```

Add to `ForgeConfig`:
```swift
var stackView: StackViewSettings?
```

## Keyboard Shortcuts

| Action | Shortcut | Config key | Active in |
|--------|----------|------------|-----------|
| Toggle Mode | `Cmd+Shift+M` | `toggleMode` | Always (existing) |
| Done | `Cmd+Return` | `stackDone` | Stack mode only |
| Hide | `Cmd+Shift+H` | `stackHide` | Stack mode only |
| Move to Back | `Cmd+Shift+]` | `stackMoveToBack` | Stack mode only |

**Mode-conditional dispatch:** Stack shortcuts are added as menu items in `ForgeApp.swift` conditionally based on `ForgeConfigStore.shared.isStackMode` (accessed directly since `@Environment` is not available in `Commands`). When `isStackMode == false`, stack menu items are absent and `selectTabRight` (`Cmd+Shift+]`) is active. When `isStackMode == true`, stack menu items replace the conflicting list-mode items. SwiftUI's `CommandGroup` with `if ForgeConfigStore.shared.isStackMode { ... } else { ... }` handles this.

All shortcuts configurable in `shortcuts` config, resolved via `KeyboardShortcuts.resolve()`.

## Files to Create

| File | Layer | Purpose |
|------|-------|---------|
| `Sources/Domain/Models/AttentionQueue.swift` | Domain | Pure queue struct |
| `Sources/Domain/Models/AttentionEvent.swift` | Domain | Event enum |
| `Sources/Domain/Ports/AttentionPort.swift` | Domain | Attention protocol |
| `Sources/Domain/Ports/NotificationPort.swift` | Domain | Notification protocol |
| `Sources/App/AttentionManager.swift` | Application | Observable service |
| `Sources/Adapters/Notification/MacNotificationAdapter.swift` | Adapter | UNUserNotificationCenter wrapper |
| `Sources/App/Views/Stack/StackView.swift` | View | Stack mode container |
| `Sources/App/Views/Stack/StackToolbar.swift` | View | Action toolbar |
| `Sources/App/Views/Stack/StackEmptyState.swift` | View | Empty queue state |

## Files to Modify

| File | Changes |
|------|---------|
| `Sources/Domain/Models/Window.swift` | Add `uuid: UUID = UUID()` |
| `Sources/Domain/Models/Pane.swift` | Add `previousCommand: String`, extend shell list in `PaneStatus.from()` |
| `Sources/Domain/Models/Workspace.swift` | Add `findWindow(byUUID:)` and `findWindow(byTmuxId:)` helpers |
| `Sources/App/WorkspaceController.swift` | Fire attention events on bell + command completion + window close |
| `Sources/App/Views/MainView.swift` | Conditional list/stack rendering |
| `Sources/App/Views/Detail/WindowTabBar.swift` | Hide/Unhide context menu items |
| `Sources/App/Views/Settings/StackModeSettingsPane.swift` | Expand stub with settings UI |
| `Sources/App/Commands/KeyboardShortcuts.swift` | 3 new stack shortcuts |
| `Sources/Adapters/Config/ForgeConfig.swift` | `StackViewSettings` struct |
| `Sources/Adapters/Config/ForgeConfigStore.swift` | Stack settings access |
| `Sources/ForgeApp.swift` | Create + inject AttentionManager, conditional menu items for stack shortcuts |

## Verification

1. **Unit test AttentionQueue**: enqueue, dequeue, insertAtFront, moveToBack, remove, idempotent enqueue, contains
2. **Build and run**: Toggle stack mode with `Cmd+Shift+M`
3. **Bell test**: Open a terminal, run `echo -e '\a'` — should appear in stack queue
4. **Command completion test**: Run `sleep 5` in a terminal — should appear in queue when it finishes
5. **Done**: Press checkmark — should advance to next queued terminal, attention cleared
6. **Hide**: Press hide — terminal should not reappear on subsequent bells
7. **Unhide**: Right-click tab in list mode → "Unhide from Stack View"
8. **Move to Back**: Press move-to-back — terminal goes to end of queue
9. **Empty state**: Clear all items — should show "Nothing needs your attention" with no toolbar
10. **Settings**: Configure notification, press "Test Notification" — macOS notification appears
11. **Mode switch**: List→Stack with active attention item → no flicker, same terminal shown
12. **Window close**: Close a window that's in the queue → auto-removed, no stale references
13. **Shortcut isolation**: In list mode, `Cmd+Shift+]` selects tab right. In stack mode, same key moves to back.
14. **Restart behavior**: Restart app → hidden set pruned, queue starts empty, all windows fresh
