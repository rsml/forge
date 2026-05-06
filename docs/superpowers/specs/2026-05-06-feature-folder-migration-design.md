# Feature-Based Folder Migration

## Context

The codebase is ~7,200 lines across ~55 files with a layer-first structure (Domain/, App/, Adapters/). It's about to 10x in size. The current flat App/ folder will become unnavigable. Moving to feature-based folders now — while the codebase is small enough to reorganize safely — prevents that.

Each feature is a vertical slice with its own hexagonal layers (domain, ports, adapters, views), but only materializes the subfolders it needs. A shared kernel (`Core/`) holds cross-feature domain models and ports.

## Target Structure

```
Sources/
  Core/                          # shared kernel (SPM target: ForgeCore)
    Models/
      Workspace.swift
      Project.swift
      Tab.swift
      Pane.swift
      AttentionQueue.swift
      AttentionEvent.swift
    Ports/
      TmuxPort.swift
      GitPort.swift
      AttentionPort.swift
      NotificationPort.swift
    StateMerger.swift
    ContentDetector.swift
    TmuxEventParser.swift

  Features/
    Attention/
      AttentionManager.swift
      MacNotificationAdapter.swift

    Sidebar/
      SidebarProjectList.swift
      ProjectRow.swift
      TruncatingText.swift
      IconButton.swift
      StatusDot.swift
      NotificationPanel.swift
      NotificationCenterRow.swift

    Stack/
      StackView.swift
      StackToolbar.swift
      StackEmptyState.swift

    TabBar/
      WindowTabBar.swift

    Terminal/
      ForgeTerminalView.swift
      TerminalArea.swift
      ProjectDetailView.swift

    CommandPalette/
      CommandPalette.swift
      CommandRegistry.swift

    ProjectPicker/
      ProjectPickerView.swift

    Settings/
      SettingsView.swift
      GeneralSettingsPane.swift
      TerminalSettingsPane.swift
      ThemeSettingsPane.swift
      ThemePreviewCard.swift
      FontSettingsPane.swift
      ShortcutsSettingsPane.swift
      ShortcutRecorder.swift
      ListModeSettingsPane.swift
      StackModeSettingsPane.swift
      AboutPane.swift

    TitleBar/
      TitleBarManager.swift      # extracted from ForgeApp.swift (~300 lines)

    Shared/
      MainView.swift
      ModalContainer.swift
      ModifierKeyMonitor.swift
      ReorderableStack.swift
      Tooltip.swift
      NotificationToast.swift
      CloseConfirmation.swift
      KeyboardShortcuts.swift

  Infrastructure/
    Tmux/
      TmuxAdapter.swift
      TmuxControlMode.swift
      TmuxCommandRunner.swift
      TmuxStateParser.swift
    Git/
      GitAdapter.swift
    Config/
      ForgeConfig.swift
      ForgeConfigStore.swift
    Theme/
      ThemeParser.swift
      ThemeDefinition.swift
    Debug/
      DebugServer.swift
    Logging/
      ForgeLog.swift

  WorkspaceController.swift      # orchestrator at root
  MenuCommands.swift             # extracted from ForgeApp.swift (~250 lines)
  ForgeApp.swift                 # composition root (~200 lines after extractions)
```

## SPM Target Changes

```swift
// Before
.target(name: "ForgeDomain", path: "Sources/Domain")
.executableTarget(name: "Forge", dependencies: ["SwiftTerm", "ForgeDomain"], path: "Sources", exclude: ["Domain"])
.testTarget(name: "ForgeTests", dependencies: ["ForgeDomain"])

// After
.target(name: "ForgeCore", path: "Sources/Core")
.executableTarget(name: "Forge", dependencies: ["SwiftTerm", "ForgeCore"], path: "Sources", exclude: ["Core"])
.testTarget(name: "ForgeTests", dependencies: ["ForgeCore"])
```

All `import ForgeDomain` → `import ForgeCore` (across all source and test files).

## ForgeApp.swift Split

The 793-line ForgeApp.swift splits into three files:

1. **ForgeApp.swift** (~200 lines) — `ForgeApp` struct, `AppDelegate` (lifecycle, window creation, appearance sync, notification observers for app-level concerns, termination), `Notification.Name` extensions, `NSColor.isLight`
2. **MenuCommands.swift** (~250 lines) — `ForgeMenuCommands` struct, extracted unchanged
3. **Features/TitleBar/TitleBarManager.swift** (~300 lines) — Visual title bar management only. Methods: `installTitleBarOverlay()`, `updateOverlayConstraints()`, `updateSplitIconVisibility()`, `updateWindowTitle()`, `stripTitleBarChrome()`, `hideTitleBarChrome(in:)`, `findView(named:in:)`, `reapplyTitleBarStyle()`, `measureTitlebarHeight()`, split/toggle `@objc` action handlers. Owns overlay NSView, constraint references, and button references. Constructor takes `NSWindow`, `WorkspaceController`, and `AttentionManager`.

**Important boundary:** The `forgeToggleMode` notification handler (lines 390-423) contains domain logic (workspace state manipulation, attention queue promotion) mixed with visual updates. The domain logic stays in AppDelegate (or moves to a `toggleMode()` method on WorkspaceController). TitleBarManager only exposes `updateSplitIconVisibility()` and `updateWindowTitle()` for AppDelegate to call after the mode switch completes.

## Design Principles

Documented in CLAUDE.md after migration (replaces the current "Where Does This Code Go?" and adapter placement rules):

- **Core/** is the shared kernel. Features depend on it, not on each other.
- **Each feature materializes only the layers it needs.** View-only features are flat files. Features with domain logic grow `Domain/`, `Ports/`, `Adapters/` subfolders as needed.
- **Infrastructure/** holds adapters that serve multiple features (Tmux, Git, Config, Theme, Debug, Logging). Feature-specific adapters live inside the feature (e.g., `MacNotificationAdapter` in `Features/Attention/`).
- **Tested domain logic lives in Core/** (the `ForgeCore` SPM target). When a feature's domain grows large enough to warrant its own test target, extract a new SPM target for it.

## Known Pre-Existing Violations (Out of Scope)

These files exceed the 300-line limit before this migration. They move to their new locations unchanged; splitting them is separate work:
- `WorkspaceController.swift` (476 lines) → `Sources/` root
- `DebugServer.swift` (361 lines) → `Infrastructure/Debug/`
- `ProjectPickerView.swift` (327 lines) → `Features/ProjectPicker/`

## Migration Steps

All moves are mechanical (git mv) except the ForgeApp.swift split which requires code extraction.

### Step 1: Rename Domain/ → Core/ and update SPM
- `git mv Sources/Domain Sources/Core`
- Update Package.swift (target name + path)
- Find-and-replace `import ForgeDomain` → `import ForgeCore` in all .swift files
- Find-and-replace `@testable import ForgeDomain` → `@testable import ForgeCore` in tests
- **Verify:** `swift build && swift test`

### Step 2: Rename Adapters/ → Infrastructure/
- `git mv Sources/Adapters Sources/Infrastructure`
- No import changes needed (Adapters aren't a separate SPM target)
- **Verify:** `swift build`

### Step 3: Create Features/ and move App/ contents
- Create feature directories
- `git mv` each file from App/Views/Sidebar/ → Features/Sidebar/, etc.
- Move AttentionManager.swift → Features/Attention/
- Move MacNotificationAdapter.swift from Infrastructure/Notification/ → Features/Attention/
- Move WorkspaceController.swift → Sources/ root
- Remove empty App/ directory
- **Verify:** `swift build`

### Step 4: Split ForgeApp.swift
- Extract `ForgeMenuCommands` → `Sources/MenuCommands.swift`
- Extract title bar management → `Sources/Features/TitleBar/TitleBarManager.swift`
- Create `TitleBarManager` class taking `NSWindow`, `WorkspaceController`, and `AttentionManager`
- Move visual methods (overlay, chrome, constraints, appearance) into TitleBarManager
- Keep domain logic in AppDelegate: the `forgeToggleMode` handler's workspace/attention mutations stay; it calls `titleBarManager.updateSplitIconVisibility()` and `titleBarManager.updateWindowTitle()` afterward
- AppDelegate creates `TitleBarManager` in `createMainWindow()`
- Title bar notification observers (fullscreen, sidebar toggle, config change, window title) register inside TitleBarManager
- Slim AppDelegate to lifecycle + wiring + mode toggle logic
- **Verify:** `swift build && swift test && make dev` (visual check of title bar)

### Step 5: Update CLAUDE.md architecture section
- Replace the source tree diagram with the new structure
- Document feature-folder principles
- Update any stale file references

## Verification

1. `swift build` succeeds after each step
2. `swift test` passes (all 52 tests) — especially after Step 1
3. `make dev` launches correctly after Step 4 — title bar overlay, chrome stripping, fullscreen all work
4. `curl localhost:7654/screenshot > /tmp/forge-screenshot.png` — visual sanity check
5. `git diff --stat` confirms no content changes in moved files (only the ForgeApp.swift split has content changes)
