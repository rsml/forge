# Forge

Native macOS tmux frontend built with SwiftUI (macOS 14+, Swift 6.0). Uses SwiftTerm for terminal rendering. Architecture follows Domain-Driven Design with Ports & Adapters (hexagonal architecture) — domain logic is isolated in `Domain/`, external concerns live in `Adapters/`, and boundaries are defined by port protocols.

## Build & Test

```bash
swift build          # compile check — always run before claiming done
swift test           # domain logic tests (ForgeTests)
make dev             # debug build + launch app
make run             # release build + launch app
```

## Project Structure

```
Sources/
  Domain/          # Models (Workspace > Project > Tab > Pane), Ports (TmuxPort)
  App/             # SwiftUI views, WorkspaceController, AttentionManager, Commands
  Adapters/        # Tmux/ (adapter, control mode, command runner)
                   # Debug/ (DebugServer), Logging/ (ForgeLog), Config/, Theme/
  ForgeApp.swift   # Entry point
```

## Debug Server (localhost:7654)

The app runs a built-in HTTP debug server. Use it to inspect and verify UI changes.

```bash
# Check if app is running
curl localhost:7654/ping

# Screenshot the app window (saves PNG to disk)
curl localhost:7654/screenshot > /tmp/forge-screenshot.png
# Then: Read /tmp/forge-screenshot.png   (to visually inspect)

# Dump workspace state as JSON (projects, tabs, panes, active states)
curl localhost:7654/state

# Read last 50 log lines
curl localhost:7654/logs

# Trigger actions
curl -X POST localhost:7654/action -d '{"action":"refresh"}'
curl -X POST localhost:7654/action -d '{"action":"selectProject","args":{"name":"my-project"}}'
curl -X POST localhost:7654/action -d '{"action":"selectTab","args":{"index":0}}'
```

Available actions: `selectProject`, `selectTab`, `addProject`, `removeProject`, `addTab`, `refresh`.

## Logs

```bash
tail -20 /tmp/forge.log
```

Log categories: `[app]`, `[control]`, `[tmux]`, `[attention]`, `[debug]`

## Naming Conventions

- **No "Forge" prefix** in function, method, or type names.
- **Project** = top-level item in the sidebar. Always top-level, never nested. Domain model: `Project`. Backed by a tmux session.
- **Tab** = item nested inside a project. Displayed in the tab bar and as sub-items in the sidebar. Domain model: `Tab`. Backed by a tmux window.
- Use "Project" and "Tab" consistently everywhere — code, UI, comments. "Session" and "Window" only appear in tmux adapter internals (command strings).

## UI Conventions

- **Tooltips**: All icon buttons use the custom tooltip system (`Tooltip.swift`), never native `.toolTip` or `.help()`. Format: label on first line, keyboard shortcut on second line (no parens). Use `.tooltip(Shortcut)` or `.tooltip(label, shortcut:)` for SwiftUI views; `.setForgeTooltip()` for AppKit views.
- **Icon buttons**: SwiftUI icons use `IconButton` (hover: secondary→primary). AppKit `NSButton` icons in the title bar must use `hoverTint: true` in `setForgeTooltip()` to match. When touching any icon button, verify it has both a tooltip and correct hover behavior.
- **Truncation tooltips**: Sidebar text (project names, tab names) uses `TruncatingText` which shows a tooltip only when ellipsized.

## Design Guidelines

### Colors & Theming
- Backgrounds load from Ghostty theme files (`resolvedTheme.background`). Default theme: `ghostty-seti`.
- UI surfaces (sidebar, toolbars, title bar spacers) layer `Color.white.opacity(0.06)` on top of the theme background for subtle depth.
- Fallback when no theme: `Color(red: 0.1, green: 0.1, blue: 0.1)`.
- Color hierarchy: `.primary` / `.labelColor` for active elements, `.secondary` / `.secondaryLabelColor` for inactive, `.tertiary` for minor hints (chevrons).
- Accent color (`Color.accentColor`) for active indicators, attention dots, and selection highlights.
- Window appearance (light/dark) is derived from theme background luminance — set automatically in `syncAppearance()`.

### Title Bar
- Window created programmatically in `AppDelegate.createMainWindow()` — not via SwiftUI `Window` scene.
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
- **List mode**: sidebar visible (120–400px, default 160px), tab bar at top, split buttons in title bar, mode toggle button hidden.
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

## Verification Checklist

Before claiming work is done:

1. `swift build` succeeds
2. `swift test` passes
3. If UI was changed: `make dev`, wait for launch, then `curl localhost:7654/screenshot > /tmp/forge-screenshot.png` and `Read /tmp/forge-screenshot.png` to visually inspect
4. Check `tail -20 /tmp/forge.log` for errors after launch
