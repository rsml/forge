# Forge

Native macOS terminal multiplexer built with SwiftUI (macOS 14+, Swift 6.0). Uses libghostty (via `GhosttyKit.xcframework`) for terminal rendering and PTY ownership. A `forged` daemon holds PTY master fds across app launches so sessions survive a quit/relaunch.

Feature-based architecture with a shared domain kernel. See `CONTEXT.md` for domain glossary, `docs/adr/` for architectural decisions.

## Build & Run

```bash
swift build          # compile check — always run before claiming done
swift test           # domain logic tests (ForgeTests)
make dev             # debug build + launch app
make run             # release build + launch app
tail -20 /tmp/forge.log   # log categories: [app] [ghostty] [daemon] [attention] [debug]
```

## Architecture

```
Sources/
  Core/                          # Shared kernel (SPM: ForgeCore). Models, Ports, pure logic.
    Models/                      # Workspace > Project > Tab > Pane, SplitNode,
                                 # AttentionQueue, AttentionEvent, AttentionTimestamps
    Ports/                       # AttentionPort, NotificationPort, PaneActivityPort, ProcessPort
    ContentDetector.swift        # Pattern matching for interactive prompts
    CloseConfirmation.swift      # Pure decision logic for close operations
    MoveTabConfirmation.swift    # Pure decision logic for move-tab confirmation
    TabReordering.swift          # Pure index math for tab reorder swap targets
    StackOrdering.swift          # Stack mode queue ordering
    CommandNameResolver.swift    # Foreground-process name resolution
    AppCommand.swift             # Typed command enum for cross-view dispatch

  Features/                      # Vertical slices — each feature owns its own layers
    Attention/                   # AttentionManager, PaneActivityWatcher, MacNotificationAdapter,
                                 # NotificationPanel, NotificationCenterRow
    Sidebar/                     # SidebarProjectList, SidebarProjectRow, SidebarTabRow, TruncatingText, IconButton, StatusDot
    Stack/                       # StackView, StackToolbar, StackEmptyState
    Terminal/                    # TerminalArea, ProjectDetailView, PaneSplitView, PaneTerminalView,
                                 # PaneDivider, WindowTabBar, WindowTab
    CommandPalette/              # CommandPalette, CommandRegistry
    ProjectPicker/               # ProjectPickerView, PickerProjectRow
    Settings/                    # SettingsView + panes (General, ListMode, StackMode, Theme, Font, Terminal, Shortcuts, About)
    TitleBar/                    # TitleBarManager, TitleBarOverlay (chrome, fullscreen)
    Shared/                      # Cross-feature: MainView, AppState, ModalOverlays, ModalContainer,
                                 # Tooltip, InlineRenameField, ReorderableStack, NotificationToast, ModifierKeyMonitor

  Infrastructure/                # Cross-feature adapters
    Terminal/                    # GhosttyRenderer (libghostty bridge), GhosttyNSView, GhosttyCallbackContext
    Process/                     # DaemonAdapter (forged RPC), DaemonActivityAdapter
    Git/                         # GitBranchPoller
    Config/                      # ForgeConfig, ForgeConfigStore, UIStatePersistence, KeyboardShortcuts
    Theme/                       # ThemeParser, ThemeDefinition, ThemeDefinition+SwiftUI, FontResolver
    Debug/                       # DebugServer, DebugServer+Responses
    Logging/                     # ForgeLog

  Daemon/                        # forged executable — PTY fd custodian
    Forged.swift, FDSocket.swift

  WorkspaceController.swift      # Thin orchestrator: owns Workspace, lifecycle, attention/git wiring
  WorkspaceController+Actions.swift   # Command methods: project/tab/pane CRUD, split, rename, etc.
  WorkspaceController+Rendering.swift # Renderer creation, daemon registration, focus/update
  MenuCommands.swift             # Menu bar commands
  ForgeApp.swift                 # Composition root + AppDelegate
```

### Dependency Direction
- **Core/** is the shared kernel. Features depend on it, not on each other.
- **Features/** are vertical slices. Each feature materializes only the layers it needs.
- **Infrastructure/** holds adapters that serve multiple features. Feature-specific adapters live inside the feature.
- Port protocols live in `Core/Ports/`. Cross-feature port implementations live in `Infrastructure/`. Feature-specific implementations live in the feature.
- No cross-imports between features. Communication goes through Core or the orchestrator.

### Where Does This Code Go?
- **Core/** — Pure functions on domain models, decision logic, value types. Zero framework imports (no AppKit, no SwiftUI). If it has no framework imports, it's probably Core.
- **Features/** — Views, feature-specific controllers, feature-specific adapters. Each feature is a self-contained vertical slice.
- **Infrastructure/** — Adapters that serve multiple features: I/O, processes, system APIs, persistence.
- **Tested domain logic lives in Core/** (the `ForgeCore` SPM target). When a feature's domain grows large enough to warrant its own test target, extract a new SPM target.

### Key Components
- **WorkspaceController** — Thin orchestrator. Owns Workspace model, runs `connect()` lifecycle (load workspace.json → pre-fetch daemon fds → start watcher + git poller). Uses `(any AttentionPort)?` — not the concrete AttentionManager.
- **PaneActivityWatcher** (`Features/Attention/`) — Event-driven attention detector. Hooks `GhosttyRenderer.onOutput` for BEL + content-match scanning; polls `PaneActivityPort` every 2s for command-completion (active→inactive transitions). Emits `AttentionEvent`s that the controller routes to AttentionManager + notifications.
- **AttentionManager** (`Features/Attention/`) — Owns the attention queue. Conforms to `AttentionPort`. Receives events from PaneActivityWatcher via the controller. Also owns MacNotificationAdapter. NotificationPanel and NotificationCenterRow live here too.
- **GitBranchPoller** (`Infrastructure/Git/`) — Polls `git rev-parse --abbrev-ref HEAD` every 5s for the active project. Posts `forgeWindowTitleChanged` on change. Independent of tmux/PTY.
- **DaemonAdapter** (`Infrastructure/Process/`) — Unix-domain socket client for the `forged` daemon. Sends/receives PTY master fds via SCM_RIGHTS. Ops: store, retrieve, list, release, is_active.
- **GhosttyRenderer** (`Infrastructure/Terminal/`) — libghostty surface bridge. Two init paths: EXEC (Ghostty forks the shell) and EXTERNAL_FD (reconnect to a PTY fd from the daemon). Exposes `onOutput` (PTY bytes), `onInput` (keyboard), and `setFocused`.
- **AppState** (`Features/Shared/`) — `@Observable` cross-feature UI state: modals, sidebar, rename state, stack actions. Dispatches `AppCommand`s. Owns `renameText` and rename lifecycle helpers. Uses `(any AttentionPort)?` and `onModeChanged` closure — no direct refs to feature implementations.
- **UIStatePersistence** (`Infrastructure/Config/`) — Save active project+tab selection, sidebar state.
- **TitleBarManager** (`Features/TitleBar/`) — All title bar visual management: overlay installation, chrome stripping, fullscreen handling, appearance sync.
- **ForgeConfigStore** — `@Observable` config store with injected `themeLoader` closure (decoupled from ThemeParser). Injected via `@Environment` in views, constructor in non-view types. `.shared` only referenced at the composition root (AppDelegate).

### Port Protocols
- **AttentionPort** — Queue management: handleEvent, markDone, hide, moveToBack, unhide, removeTab, pruneStaleHiddenEntries, promoteToFront, seedQueue, pruneResolved. Properties: currentTabUUID, queueCount, timestamps.
- **NotificationPort** — System notification delivery.
- **PaneActivityPort** — `query(paneIds:) -> [PaneActivity]`. Reports which panes have a foreground process other than the controlling shell. Implementations fail open. Today's adapter: `DaemonActivityAdapter` (queries forged's `is_active` op).
- **ProcessPort** / **PersistencePort** (`Core/Ports/ProcessPort.swift`) — Pane creation and PTY-fd persistence contracts. DaemonAdapter implements PersistencePort.

### Blessed Patterns
- One pattern per problem. If the codebase already solves something, use that solution — don't invent a parallel one.
- One dispatch mechanism per class of operation. Don't mix NotificationCenter, direct method calls, and closures for the same kind of action.
- Event-driven attention: PTY output → `onOutput` callback → ContentDetector + BEL scan → AttentionEvent → AttentionManager.
- forged daemon owns fds; Forge quits with `_exit(0)` to skip AppKit teardown and avoid SIGHUP to child shells.

### Theming
- **ThemeColor** — Platform-agnostic `(red: Double, green: Double, blue: Double)` struct in `ThemeDefinition.swift`. No SwiftUI import.
- **ThemeDefinition+SwiftUI.swift** — Extension adding `.color` computed property that converts `ThemeColor` to `SwiftUI.Color`.
- **ThemeParser** — Imports Foundation only. Returns `ThemeColor` values. `loadTheme(id:)` searches Ghostty theme paths.
- **ForgeConfigStore** — Receives a `themeLoader: (String) -> ThemeDefinition?` closure at init (wired to `ThemeParser.loadTheme` at the composition root). Never imports ThemeParser directly.
- **FontResolver** (`Infrastructure/Theme/`) — Resolves terminal fonts: config family → Ghostty config → Nerd Font fallbacks → system monospaced.
- Views access theme colors via `configStore.resolvedTheme?.background.color` (the `.color` accessor converts ThemeColor → SwiftUI.Color).

### File Discipline
- **Hard limit: 300 lines per file.** Files over 300 lines must be split before merging. Find a natural seam — don't just chop arbitrarily.
- One type per file, named to match the type. Extensions in `Type+Category.swift` files are fine.

## Rules

### Naming
- **No "Forge" prefix** in function, method, or type names.
- **Project** = top-level sidebar item. Domain model: `Project`. Has a working directory; owns its tabs.
- **Tab** = item nested inside a project. Domain model: `Tab`. Owns its panes and split tree.
- **Pane** = a single terminal surface. Backed by a PTY fd held by the daemon and a libghostty surface for rendering.

### State Ownership
- `WorkspaceController` is the single `@Observable` object that owns workspace state. All views consume it via `@Environment`.
- `AppState` owns cross-feature UI state (modals, sidebar visibility, rename state). Injected via `@Environment`.
- `@State` is only for local, view-scoped UI state (hover, animation). Never domain state.
- Domain models (`Workspace`, `Project`, `Tab`, `Pane`) are `@Observable @MainActor`.
- No `.shared` singletons consumed by views or non-view types. Inject via `@Environment` (views) or constructor (non-view types). `.shared` is permitted only at the composition root (`AppDelegate`).

### Concurrency
- `@MainActor` for all observable state, ports, and controllers.
- Structured concurrency (`async`/`await`, `Task {}`, `TaskGroup`) for async work.
- `DispatchQueue` only in adapter internals where required by underlying APIs (Ghostty I/O thread, EXTERNAL_FD read thread).

### Error Handling
- **Request-response adapter calls** (e.g., DaemonAdapter ops): propagate failure to the caller. Show a toast on user-visible failure.
- **Fail-open for activity polling**: a wedged daemon must never block the close path. `DaemonActivityAdapter` has a 200ms timeout and reports all-idle on timeout.
- **Optimistic UI updates**: permitted only for drag interactions (reorder, swap) where latency matters.

### Testing Strategy
- **Core**: TDD with Swift Testing (`@Test`, `#expect`). Pure logic, no side effects.
- **Infrastructure**: Integration tests when behavior depends on external processes.
- **UI**: Visual verification via debug server screenshots.

### Code Discipline
- No speculative code — every line serves a current requirement.
- No unused abstractions — delete code that has no caller.
- No premature helpers — three similar lines are better than a premature abstraction.

## UI Reference

### Colors & Theming
- Backgrounds load from Ghostty theme files (`resolvedTheme.background.color`). Default theme: `ghostty-seti`.
- UI surfaces (sidebar, toolbars, title bar spacers) layer `Color.white.opacity(0.06)` on top of the theme background for subtle depth.
- Fallback when no theme: `Color(red: 0.1, green: 0.1, blue: 0.1)`.
- Color hierarchy: `.primary` / `.labelColor` for active elements, `.secondary` / `.secondaryLabelColor` for inactive, `.tertiary` for minor hints (chevrons).
- Accent color (`Color.accentColor`) for active indicators, attention dots, and selection highlights.
- Window appearance (light/dark) is derived from theme background luminance — set automatically in `TitleBarManager.syncAppearance()`.

### Components
- **Tooltips**: Custom tooltip system (`Tooltip.swift`), never native `.toolTip` or `.help()`. Format: label on first line, keyboard shortcut on second line (no parens). Use `.tooltip(Shortcut)` or `.tooltip(label, shortcut:)` for SwiftUI views; `.setForgeTooltip()` for AppKit views.
- **Icon buttons**: SwiftUI icons use `IconButton` (hover: secondary -> primary). AppKit `NSButton` icons in the title bar must use `hoverTint: true` in `setForgeTooltip()` to match. When touching any icon button, verify it has both a tooltip and correct hover behavior.
- **Truncation tooltips**: Sidebar text (project names, tab names) uses `TruncatingText` which shows a tooltip only when ellipsized.
- **Inline rename**: `InlineRenameField` (in `Features/Shared/`) used by both Sidebar and TabBar. Rename state (`renameText`, `renamingTabId`, `renamingProjectId`) lives in `AppState` — not drilled via params.
- **Modal overlays**: `ModalOverlays` ViewModifier handles CommandPalette, ProjectPicker, and NotificationPanel presentation. MainView applies it — individual modals don't manage their own visibility.

### Title Bar
- Window created programmatically in `AppDelegate.createMainWindow()` — not via SwiftUI `Window` scene. Title bar managed by `TitleBarManager` (`Features/TitleBar/`).
- `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `titlebarSeparatorStyle = .none`.
- `_NSTitlebarDecorationView` and `NSVisualEffectView` inside the title bar are **hidden** (not removed) — more resilient to macOS re-adding them during layout passes.
- Stripping runs on a 100ms repeating timer for 3s at launch, plus on `didBecomeKeyNotification` and after fullscreen exit.
- A custom overlay NSView is installed on the title bar containing: path label, branch label, mode toggle button, and split buttons.
- Title bar background matches sidebar color (theme background + white overlay) for visual continuity.

### Fullscreen
- On `willEnterFullScreen`: hide split icons, disable `titlebarAppearsTransparent` on macOS 15.3+ (workaround for OS bug).
- On `didExitFullScreen`: re-measure title bar height, restore `titlebarAppearsTransparent`, re-strip chrome, reinstall overlay. Fullscreen exit resets title bar properties — everything must be reapplied.
- SwiftUI views also observe fullscreen notifications to toggle titlebar spacer visibility.

### Stack Mode vs List Mode
- **List mode**: sidebar visible (120-400px, default 160px), tab bar at top, split buttons in title bar, mode toggle button hidden.
- **Stack mode**: sidebar hidden, `StackToolbar` with action buttons above or below terminal (configurable via `config.stackView.toolbarPosition`, default "bottom"), mode toggle button visible in title bar at 82px from left.
- Title bar overlay constraints shift between modes — path label leading changes to accommodate mode toggle button.

### Animations
- **Spring** for interactive feedback: drag reorder (`response: 0.25, dampingFraction: 0.85`), toast show (`duration: 0.4, bounce: 0.2`).
- **EaseInOut** for structural changes: sidebar toggle, chevron rotation (`0.2s`).
- **EaseIn** for dismiss: stack card flyout (`0.35s`, scale 0.85 + offset -800 + fade).
- **EaseOut** for fade-away: toast dismiss (`0.3s`), tooltip fade-out (`0.1s`).
- Tooltip show delay: `0.5s`, fade-in: `0.15s`.

### Corner Radii
- Sidebar row hover: 4px. Tooltip pill: 6px. Modals/toasts: 12px. Inline rename field: 3px. Tab active indicator: 1px.

## Verification

### Debug Server (localhost:7654)

```bash
curl localhost:7654/ping                                    # check if app is running
curl localhost:7654/screenshot > /tmp/forge-screenshot.png  # screenshot (then Read to inspect)
curl localhost:7654/state                                   # workspace state as JSON
curl localhost:7654/logs                                    # last 50 log lines
curl -X POST localhost:7654/action -d '{"action":"selectProject","args":{"name":"my-project"}}'
curl -X POST localhost:7654/action -d '{"action":"selectTab","args":{"index":0}}'
```

Available actions: `selectProject`, `selectTab`, `addProject`, `removeProject`, `addTab`, `splitPane`.

### Checklist

Before claiming work is done:

1. `swift build` succeeds
2. `swift test` passes
3. If UI was changed: `make dev`, wait for launch, then `curl localhost:7654/screenshot > /tmp/forge-screenshot.png` and `Read /tmp/forge-screenshot.png` to visually inspect
4. Check `tail -20 /tmp/forge.log` for errors after launch
