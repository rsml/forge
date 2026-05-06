# Forge

Native macOS tmux frontend built with SwiftUI (macOS 14+, Swift 6.0). Uses SwiftTerm for terminal rendering.

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

## Verification Checklist

Before claiming work is done:

1. `swift build` succeeds
2. `swift test` passes
3. If UI was changed: `make dev`, wait for launch, then `curl localhost:7654/screenshot > /tmp/forge-screenshot.png` and `Read /tmp/forge-screenshot.png` to visually inspect
4. Check `tail -20 /tmp/forge.log` for errors after launch
