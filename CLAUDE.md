# Forge

Native macOS tmux frontend built with SwiftUI (macOS 14+, Swift 6.0). Uses SwiftTerm for terminal rendering.
Feature-based architecture with a shared domain kernel. See `CONTEXT.md` for domain glossary, `docs/adr/` for architectural decisions.

## Build & Run

```bash
swift build          # compile check — always run before claiming done
swift test           # domain logic tests (ForgeTests)
make dev             # debug build + launch app
make run             # release build + launch app
tail -20 /tmp/forge.log   # log categories: [app] [control] [tmux] [attention] [debug]
```

## Architecture

```
Sources/
  Core/              # Shared kernel (SPM: ForgeCore). Models, Ports, pure logic.
  Features/          # Vertical slices — each feature owns its own layers.
    Attention/       # AttentionManager, MacNotificationAdapter
    Sidebar/         # SidebarProjectList, ProjectRow, etc.
    Stack/           # StackView, StackToolbar
    TabBar/          # WindowTabBar
    Terminal/        # ForgeTerminalView, TerminalArea, ProjectDetailView
    CommandPalette/  # CommandPalette, CommandRegistry
    ProjectPicker/   # ProjectPickerView
    Settings/        # All settings panes
    TitleBar/        # TitleBarManager, overlay, chrome stripping
    Shared/          # Cross-feature UI: MainView, Tooltip, KeyboardShortcuts, etc.
  Infrastructure/    # Cross-feature adapters: Tmux/, Git/, Config/, Theme/, Debug/, Logging/
  WorkspaceController.swift  # Orchestrator
  ForgeApp.swift              # Composition root + AppDelegate
  MenuCommands.swift          # Menu bar commands
```

### Dependency Direction
- **Core/** is the shared kernel. Features depend on it, not on each other.
- **Features/** are vertical slices. Each feature materializes only the layers it needs (flat files for view-only, `Domain/`/`Ports/`/`Adapters/` subfolders when it has its own domain logic).
- **Infrastructure/** holds adapters that serve multiple features. Feature-specific adapters live inside the feature.
- Port protocols live in `Core/Ports/`. Cross-feature port implementations live in `Infrastructure/`. Feature-specific implementations live in the feature.
- No cross-imports between features. Communication goes through Core or the orchestrator.

### Where Does This Code Go?
- **Core/** — Pure functions on domain models, decision logic, value types. Zero framework imports (no AppKit, no SwiftUI). If it has no framework imports, it's probably Core.
- **Features/** — Views, feature-specific controllers, feature-specific adapters. Each feature is a self-contained vertical slice.
- **Infrastructure/** — Adapters that serve multiple features: I/O, processes, system APIs, persistence.
- **Tested domain logic lives in Core/** (the `ForgeCore` SPM target). When a feature's domain grows large enough to warrant its own test target, extract a new SPM target.

### Blessed Patterns
- One pattern per problem. If the codebase already solves something, use that solution — don't invent a parallel one.
- One dispatch mechanism per class of operation. Don't mix NotificationCenter, direct method calls, and closures for the same kind of action.
- Tmux control mode (`-CC`) for push-based state updates.
- Isolated tmux socket: `-L forge` with custom config `forge-tmux.conf`.
- Bundled tmux binary looked up next to executable, falls back to system.

### File Discipline
- **Hard limit: 300 lines per file.** Files over 300 lines must be split before merging. Find a natural seam — don't just chop arbitrarily.
- One type per file, named to match the type.

## Rules

### Naming
- **No "Forge" prefix** in function, method, or type names.
- **Project** = top-level sidebar item. Domain model: `Project`. Backed by a tmux session.
- **Tab** = item nested inside a project. Domain model: `Tab`. Backed by a tmux window.
- Use "Project" and "Tab" consistently everywhere. "Session" and "Window" only appear in tmux adapter internals (command strings).

### State Ownership
- `WorkspaceController` is the single `@Observable` object that owns workspace state. All views consume it via `@Environment`.
- `@State` is only for local, view-scoped UI state (hover, animation, text field values). Never domain state.
- Domain models (`Workspace`, `Project`, `Tab`, `Pane`) are `@Observable @MainActor`.
- No `.shared` singletons consumed by views. Inject via `@Environment` or constructor. Singletons are permitted only at the composition root (`ForgeApp`/`AppDelegate`).

### Concurrency
- `@MainActor` for all observable state, ports, and controllers.
- Structured concurrency (`async`/`await`, `Task {}`, `TaskGroup`) for async work.
- `DispatchQueue` only in adapter internals where required by underlying APIs.

### Error Handling
- Adapter calls that mutate state must propagate failure. Fire-and-forget `Task {}` is only acceptable for read-only side effects (logging, analytics).
- When a mutating adapter call fails, surface feedback to the user (toast, log, or revert optimistic update).

### Testing Strategy
- **Core**: TDD with Swift Testing (`@Test`, `#expect`). Pure logic, no side effects.
- **Infrastructure**: Integration tests against real tmux when needed.
- **UI**: Visual verification via debug server screenshots.

### Code Discipline
- No speculative code — every line serves a current requirement.
- No unused abstractions — delete code that has no caller.
- No premature helpers — three similar lines are better than a premature abstraction.

## UI Reference

### Colors & Theming
- Backgrounds load from Ghostty theme files (`resolvedTheme.background`). Default theme: `ghostty-seti`.
- UI surfaces (sidebar, toolbars, title bar spacers) layer `Color.white.opacity(0.06)` on top of the theme background for subtle depth.
- Fallback when no theme: `Color(red: 0.1, green: 0.1, blue: 0.1)`.
- Color hierarchy: `.primary` / `.labelColor` for active elements, `.secondary` / `.secondaryLabelColor` for inactive, `.tertiary` for minor hints (chevrons).
- Accent color (`Color.accentColor`) for active indicators, attention dots, and selection highlights.
- Window appearance (light/dark) is derived from theme background luminance — set automatically in `syncAppearance()`.

### Components
- **Tooltips**: Custom tooltip system (`Tooltip.swift`), never native `.toolTip` or `.help()`. Format: label on first line, keyboard shortcut on second line (no parens). Use `.tooltip(Shortcut)` or `.tooltip(label, shortcut:)` for SwiftUI views; `.setForgeTooltip()` for AppKit views.
- **Icon buttons**: SwiftUI icons use `IconButton` (hover: secondary -> primary). AppKit `NSButton` icons in the title bar must use `hoverTint: true` in `setForgeTooltip()` to match. When touching any icon button, verify it has both a tooltip and correct hover behavior.
- **Truncation tooltips**: Sidebar text (project names, tab names) uses `TruncatingText` which shows a tooltip only when ellipsized.

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
curl -X POST localhost:7654/action -d '{"action":"refresh"}'
curl -X POST localhost:7654/action -d '{"action":"selectProject","args":{"name":"my-project"}}'
curl -X POST localhost:7654/action -d '{"action":"selectTab","args":{"index":0}}'
```

Available actions: `selectProject`, `selectTab`, `addProject`, `removeProject`, `addTab`, `refresh`.

### Checklist

Before claiming work is done:

1. `swift build` succeeds
2. `swift test` passes
3. If UI was changed: `make dev`, wait for launch, then `curl localhost:7654/screenshot > /tmp/forge-screenshot.png` and `Read /tmp/forge-screenshot.png` to visually inspect
4. Check `tail -20 /tmp/forge.log` for errors after launch
