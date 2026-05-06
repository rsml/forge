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
  Domain/          # Models (Workspace > Session > Window > Pane), Ports (TmuxPort)
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

# Dump workspace state as JSON (sessions, windows, panes, active states)
curl localhost:7654/state

# Read last 50 log lines
curl localhost:7654/logs

# Trigger actions
curl -X POST localhost:7654/action -d '{"action":"refresh"}'
curl -X POST localhost:7654/action -d '{"action":"selectSession","args":{"name":"my-session"}}'
curl -X POST localhost:7654/action -d '{"action":"selectWindow","args":{"index":0}}'
```

Available actions: `selectSession`, `selectWindow`, `addSession`, `removeSession`, `addWindow`, `refresh`.

## Logs

```bash
tail -20 /tmp/forge.log
```

Log categories: `[app]`, `[control]`, `[tmux]`, `[attention]`, `[debug]`

## Naming Conventions

- **No "Forge" prefix** in function, method, or type names — the module boundary provides namespace. Exception: notification names (`.forgeCommandPalette`) and config types (`ForgeConfig`) that cross module boundaries.
- **Project** = a tmux session. Always top-level, never nested. Displayed in the sidebar. Maps to `Session` in the domain model.
- **Tab** = a tmux window inside a project. Always nested inside a project. Displayed in the tab bar and as sub-items in the sidebar. Maps to `Window` in the domain model.
- Use "Project" and "Tab" consistently in all user-facing text (tooltips, labels, menu items, command palette). Never use "Session" or "Window" in UI — those are domain model names only.

## UI Conventions

- **Tooltips**: All icon buttons use the custom tooltip system (`Tooltip.swift`), never native `.toolTip` or `.help()`. Format: label on first line, keyboard shortcut on second line (no parens). Use `.tooltip(Shortcut)` or `.tooltip(label, shortcut:)` for SwiftUI views; `.setForgeTooltip()` for AppKit views.
- **Icon buttons**: SwiftUI icons use `IconButton` (hover: secondary→primary). AppKit `NSButton` icons in the title bar must use `hoverTint: true` in `setForgeTooltip()` to match. When touching any icon button, verify it has both a tooltip and correct hover behavior.
- **Truncation tooltips**: Sidebar text (project names, tab names) uses `TruncatingText` which shows a tooltip only when ellipsized.

## Verification Checklist

Before claiming work is done:

1. `swift build` succeeds
2. `swift test` passes
3. If UI was changed: `make dev`, wait for launch, then `curl localhost:7654/screenshot > /tmp/forge-screenshot.png` and `Read /tmp/forge-screenshot.png` to visually inspect
4. Check `tail -20 /tmp/forge.log` for errors after launch
