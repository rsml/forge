# Native PTY Architecture

## Problem

Forge uses tmux control mode (-CC) as a middleman between Ghostty terminal surfaces and shell processes. This causes:

- **Grid mismatches**: two independent layout engines (SwiftUI and tmux) computing cell dimensions differently
- **Encoding overhead**: PTY output → tmux octal encoding → decode → feed to Ghostty
- **Input encoding**: keystrokes → send-keys command encoding → tmux → PTY write
- **TUI incompatibility**: Claude Code's fullscreen mode is documented as incompatible with tmux -CC
- **State reconciliation**: continuous sync between Forge's model and tmux's model, with timing races
- **~2000 lines of adapter code**: TmuxControlMode, TmuxCommandRunner, TmuxStateParser, TmuxSyncEngine, OutputRouter, StateMerger, resize negotiations

The root cause: Ghostty is used as a renderer (MANUAL IO mode — just a display fed external bytes) when it should be used as a terminal (owning the PTY, handling I/O natively).

## Solution

Three clean layers with no overlap:

| Layer | Responsibility | Owns |
|---|---|---|
| **Forge** | Project/tab organization, sidebar, attention, config, UI chrome | Domain model, SwiftUI views |
| **Ghostty** | Terminal: PTY I/O, rendering, input encoding, resize, all VT features | Surface lifecycle, data path |
| **forged** | PTY file descriptor persistence across app restarts | Master fd duplicates |

Ghostty surfaces own their PTYs natively. No middleman in the data path. The daemon is an idle fd vault — not in the data path during normal operation.

## Architecture

### Data Flow

```
NORMAL OPERATION:
  User types → Ghostty Termio thread → PTY write (direct)
  PTY output → Ghostty Termio thread → VT parse → Metal render (direct)
  Resize → Ghostty → ioctl(TIOCSWINSZ) on its own fd (direct)

FORGE QUITS:
  Forge sends each PTY master fd to daemon via sendmsg(SCM_RIGHTS)
  Daemon holds fd duplicates → processes keep running
  Forge exits

FORGE RECONNECTS:
  Daemon sends fds back to Forge
  New Ghostty surfaces created with pre-existing fds
  Surfaces resume reading/writing → terminal content reappears
```

### Port Protocols

Replace `TmuxQueryPort` (7 methods) + `TmuxCommandPort` (15 methods) + `TmuxControlPort` (3 methods) with:

```swift
/// Creates and manages terminal processes.
@MainActor
public protocol ProcessPort {
    /// Spawn a new shell process in a PTY. Returns a handle for the surface.
    func create(cwd: String, env: [String: String], cols: Int, rows: Int) -> PaneHandle

    /// Reconnect to an existing PTY fd (from daemon on app restart).
    func reconnect(fd: Int32, cols: Int, rows: Int) -> PaneHandle

    /// Kill the process and close the PTY.
    func kill(_ handle: PaneHandle)

    /// Resize the PTY (calls ioctl TIOCSWINSZ — instant, no round-trip).
    func resize(_ handle: PaneHandle, cols: Int, rows: Int)

    /// Current process info (command name, cwd, pid, running/idle).
    func status(_ handle: PaneHandle) -> PaneStatus
}

/// Persists PTY file descriptors across app restarts.
public protocol PersistencePort {
    /// Store a PTY master fd for safekeeping. Daemon holds a dup.
    func store(paneId: String, fd: Int32) async

    /// Retrieve a stored fd on reconnect. Returns nil if process died.
    func retrieve(paneId: String) async -> Int32?

    /// List all persisted panes (for workspace reconstruction on restart).
    func list() async -> [PersistedPaneInfo]

    /// Release a stored fd (pane was intentionally closed).
    func release(paneId: String) async
}
```

7 methods total (down from 25). No terminal rendering concerns leak into the ports.

### Domain Model Changes

The domain model (`Workspace > Project > Tab > Pane`) is unchanged. What changes:

- `Pane.id` — currently a tmux pane ID (e.g., `%2`). Becomes a Forge-generated UUID.
- `Project.id` — currently a tmux session ID (e.g., `$1`). Becomes a Forge-generated UUID.
- `Tab.id` — currently a tmux window ID (e.g., `@1`). Becomes a Forge-generated UUID.
- `Tab.layout` — currently a tmux layout string. Replaced by a Forge-owned `SplitNode` tree (already exists in the model).

The model no longer mirrors external state. Forge IS the source of truth.

### GhosttyKit Surface Modes

Currently Forge uses `GHOSTTY_SURFACE_IO_MANUAL` (Ghostty is a dumb display). The new architecture needs:

**For new panes:** Ghostty's default mode — it calls `forkpty()`, spawns the shell, owns the PTY. Full native performance. All terminal features work automatically.

**For reconnected panes:** A new mode where Ghostty accepts a pre-existing PTY master fd instead of calling `forkpty()`. The Termio thread reads/writes this fd natively — same performance as default mode, but the fd came from the daemon instead of `forkpty()`.

This requires adding an `io_fd` field to `ghostty_surface_config_s` in the GhosttyKit fork:

```c
typedef struct {
    // ...existing fields...
    ghostty_surface_io_e io_mode;  // EXEC (default), MANUAL, or EXTERNAL_FD
    int io_fd;                      // pre-existing PTY master fd (for EXTERNAL_FD mode)
    // ...
} ghostty_surface_config_s;
```

### forged (Forge Daemon)

A minimal process (~400 lines) bundled inside Forge.app:

- **Listens** on a Unix domain socket (`/tmp/forge-daemon-<uid>.sock`)
- **Protocol**: JSON control messages + fd passing via `sendmsg(SCM_RIGHTS)`
- **Operations**:
  - `store {pane_id, metadata}` + fd via ancillary data → daemon holds the fd
  - `retrieve {pane_id}` → daemon sends fd back via ancillary data
  - `list` → returns all stored panes with metadata (cwd, pid, alive status)
  - `release {pane_id}` → daemon closes the fd (process gets SIGHUP)
- **Lifecycle**: launched by Forge on first run, stays alive via launchd or self-daemonize
- **State**: in-memory only (fd table + metadata). No disk persistence needed — the fds ARE the state.
- **Crash resilience**: if daemon crashes, fds close → processes die. Acceptable for v1. Later: launchd `KeepAlive` for automatic restart.

### Workspace Persistence

With tmux gone, Forge needs to persist the workspace structure to disk:

```json
{
  "projects": [
    {
      "id": "uuid-1",
      "name": "Assistants",
      "path": "/Users/ross/Library/Assistants",
      "tabs": [
        {
          "id": "uuid-2",
          "name": "claude",
          "panes": [
            { "id": "uuid-3", "cwd": "/Users/ross/Library/Assistants" },
            { "id": "uuid-4", "cwd": "/Users/ross/Library/Assistants" }
          ],
          "splitLayout": { "direction": "horizontal", "ratio": 0.5 }
        }
      ]
    }
  ]
}
```

Saved to `~/.config/forge/workspace.json` on every structural change (add/remove project/tab/pane, rename). Split ratios saved on divider drag end.

On startup: read workspace.json → connect to daemon → retrieve fds → create Ghostty surfaces.

### Attention System

Currently driven by tmux events (`%bell`, silence subscriptions, content scanning via `capture-pane`). Replacements:

- **Bell**: Ghostty surfaces emit a bell callback when they receive `\a` (BEL). Wire this to AttentionManager.
- **Command completion**: monitor each pane's foreground process via `tcgetpgrp()` on the PTY fd. When the foreground process changes from non-shell to shell, the command completed.
- **Content scanning**: Ghostty has screen content access via `ghostty_surface_inspector`. Or: use the VT parser's output hook to scan lines as they arrive (zero-latency vs the current 5-second poll).
- **Silence detection**: track the last `%output` timestamp per pane. If no output for 2 seconds and the pane was previously active, mark as needing attention.

### Input Handling

**Deleted entirely.** No more `sendKeyEvent()`, no `send-keys` encoding, no `C-c` key name mapping, no hex encoding for escape sequences, no literal quoting for spaces/semicolons.

Ghostty's native key handling takes over:
- `keyDown` → Ghostty's Termio thread → PTY write
- Ctrl+C → Ghostty encodes as 0x03 → PTY write
- All special keys (arrows, home, end, function keys) handled by Ghostty's key encoder
- Kitty keyboard protocol works correctly (Ghostty supports it natively)

### Resize Handling

**Deleted entirely.** No more `refresh-client -C`, `resize-window`, `resize-pane`, cell size computation, divider width matching, batched flush, suppress flags.

Ghostty handles resize:
1. SwiftUI frame changes → `GhosttyNSView.setFrameSize` → `ghostty_surface_set_size`
2. Ghostty internally computes new cols/rows from pixel dimensions
3. Ghostty calls `ioctl(fd, TIOCSWINSZ, &size)` on its own PTY
4. Shell receives SIGWINCH → redraws
5. New output → Ghostty renders

One source of truth. Zero mismatch possible.

## What Gets Deleted

| File | Lines | Why |
|---|---|---|
| TmuxAdapter.swift | ~250 | Replaced by ProcessAdapter (direct PTY) |
| TmuxControlMode.swift | ~230 | No control mode |
| TmuxCommandRunner.swift | ~100 | No tmux commands |
| TmuxStateParser.swift | ~150 | No tmux state to parse |
| TmuxSyncEngine.swift | ~300 | No state reconciliation |
| TmuxOutputDecoder.swift | ~50 | No octal decoding |
| TmuxEventParser.swift | ~50 | No tmux events |
| StateMerger.swift | ~150 | Forge IS the source of truth |
| OutputRouter.swift | ~50 | Ghostty reads its own PTY |
| forge-tmux.conf | ~30 | No tmux |
| Bundled tmux binary | ~2MB | No tmux |
| GhosttyNSView input bypass | ~80 | Ghostty handles input natively |
| WorkspaceController+Rendering resize logic | ~100 | Ghostty handles resize |
| **Total** | **~1540 lines + 2MB binary** | |

## What Gets Added

| Component | Lines | Purpose |
|---|---|---|
| forged daemon | ~400 | fd vault for persistence |
| ProcessAdapter | ~150 | ProcessPort implementation (create/kill/resize via Ghostty) |
| DaemonAdapter | ~150 | PersistencePort implementation (Unix socket + fd passing) |
| WorkspacePersistence | ~100 | JSON save/load of project/tab/pane structure |
| GhosttyKit io_fd mode | ~50 | Accept pre-existing PTY fd (Zig change in vendor/ghostty) |
| Attention adapters | ~100 | Bell callback, process monitoring, content scanning |
| **Total** | **~950 lines** | |

Net: **-590 lines, -2MB binary, and every rendering bug eliminated.**

## Migration Plan

### Phase 1: Direct PTY mode (no persistence)

- Add `GHOSTTY_SURFACE_IO_EXEC` mode to GhosttyRenderer (Ghostty creates PTY, spawns shell)
- Create `ProcessAdapter` implementing `ProcessPort`
- Wire WorkspaceController to use ProcessPort instead of TmuxPort for pane creation
- Remove all input bypass code from GhosttyNSView (let Ghostty handle keys)
- Remove all resize logic from WorkspaceController+Rendering
- Remove OutputRouter
- Keep tmux code for fallback (feature flag: `nativePTY` in config)
- **Result**: terminals work perfectly, but closing Forge kills all processes

### Phase 2: forged daemon

- Build forged binary (Unix socket server, fd storage, JSON protocol)
- Create `DaemonAdapter` implementing `PersistencePort`
- On pane creation: send fd to daemon for safekeeping
- On app quit: daemon keeps fds → processes survive
- On app restart: retrieve fds from daemon, create surfaces with `io_fd` mode
- Add `WorkspacePersistence` for project/tab structure
- **Result**: full persistence, tmux-equivalent experience

### Phase 3: Cleanup

- Remove all tmux infrastructure files
- Remove bundled tmux binary from Makefile
- Update CONTEXT.md and domain glossary (remove tmux references)
- Remove feature flag — native PTY is the only mode
- Update CLAUDE.md architecture documentation
- **Result**: clean codebase, no tmux dependency

## Risks

| Risk | Mitigation |
|---|---|
| GhosttyKit io_fd mode requires Zig changes | We own the fork. The change is ~50 lines in Termio. |
| Daemon crash kills all processes | launchd KeepAlive for auto-restart. Daemon is ~400 lines with minimal failure modes. |
| No remote/SSH session sharing | Out of scope. Forge is a local app. Add tmux-mode back as an optional feature later if needed. |
| Attention system needs new backends | Bell is trivial (Ghostty callback). Process monitoring via tcgetpgrp is standard. Content scanning can use Ghostty's inspector API. |
| Split layout persistence | Already solved — SplitNode tree + proportions stored in workspace.json. |
