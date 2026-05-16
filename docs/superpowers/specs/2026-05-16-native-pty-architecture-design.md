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
  fd is also dup'd to daemon (idle, not reading — just keeping alive)

FORGE QUITS:
  Forge dumps each surface's scrollback to ~/.config/forge/scrollback/<pane-id>
  Forge exits — Ghostty surfaces close their fd copies
  Daemon's dup'd fds keep PTYs alive → processes keep running

FORGE RECONNECTS:
  Read workspace.json → connect to daemon → retrieve fds
  Create Ghostty surfaces with EXTERNAL_FD mode (pre-existing PTY fd)
  Feed saved scrollback into each surface (visual continuity)
  Send SIGWINCH to each PTY (forces shell/TUI app to redraw at current size)
  Surfaces resume reading/writing → live terminal content appears
```

### Port Protocols

Replace `TmuxQueryPort` (7 methods) + `TmuxCommandPort` (15 methods) + `TmuxControlPort` (3 methods) with:

```swift
/// Creates and manages terminal processes.
/// Resize and status are NOT here — Ghostty handles resize internally
/// via setFrameSize → ioctl(TIOCSWINSZ), and status arrives via
/// GhosttyKit's action_cb (COMMAND_FINISHED, CHILD_EXITED, BELL).
@MainActor
public protocol ProcessPort {
    /// Spawn a new shell process in a PTY. Returns a handle for the surface.
    /// Size comes from the SwiftUI view frame, not the caller.
    func create(cwd: String, env: [String: String]) -> PaneHandle

    /// Reconnect to an existing PTY fd (from daemon on app restart).
    func reconnect(fd: Int32) -> PaneHandle

    /// Kill the process and release the daemon's fd. Order matters:
    /// tell daemon to release first, then close the surface.
    func kill(_ handle: PaneHandle)
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

7 methods total (down from 25). No resize, no status polling — those are event-driven from GhosttyKit's `action_cb`.

### GhosttyKit action_cb (Event-Driven Status)

Currently stubbed in GhosttyApp.swift. Must be fully implemented as a Phase 1 prerequisite. Ghostty delivers these events via the action callback:

| Action | Maps to |
|---|---|
| `GHOSTTY_ACTION_BELL` | `AttentionManager.handleEvent(.bell)` |
| `GHOSTTY_ACTION_CHILD_EXITED` | Pane cleanup, "[Process completed]" UI |
| `GHOSTTY_ACTION_COMMAND_FINISHED` | `AttentionManager.handleEvent(.commandCompleted)` |
| `GHOSTTY_ACTION_SET_TITLE` | Tab title update |
| `GHOSTTY_ACTION_CELL_SIZE` | `terminalCellSize` for divider widths |
| `GHOSTTY_ACTION_WRITE_CLIPBOARD` | NSPasteboard write (already wired) |
| `GHOSTTY_ACTION_READ_CLIPBOARD` | NSPasteboard read (currently stubbed — must implement) |

This replaces TmuxSyncEngine's poll-based attention detection with zero-latency push events.

### Domain Model Changes

The domain model (`Workspace > Project > Tab > Pane`) shape is unchanged. What changes:

- **IDs**: `Pane.id`, `Tab.id`, `Project.id` stay as `String` type but contain Forge-generated UUIDs instead of tmux IDs (`%2`, `@1`, `$1`). `Tab.uuid` (the existing stable UUID) becomes redundant — `Tab.id` is now the stable identifier.
- **`Tab.layout`**: currently `String?` holding a raw tmux layout string. Add a new `Tab.splitTree: SplitNode?` property that Forge owns directly. `SplitNode` already exists but needs to be stored on the model, not just parsed transiently.
- **`Workspace.findTab(byTmuxId:)`**: deleted. Only `findTab(byUUID:)` remains.
- **`perProjectActiveTabId: [String: String]`**: unchanged in shape, just uses UUID strings.

### GhosttyKit Surface Modes

**For new panes:** `GHOSTTY_SURFACE_IO_EXEC` (default) — Ghostty calls `forkpty()`, spawns the shell, owns the PTY. Full native performance. All terminal features work.

**For reconnected panes:** `GHOSTTY_SURFACE_IO_EXTERNAL_FD` (new) — Ghostty accepts a pre-existing PTY master fd. The Termio thread reads/writes this fd natively — same performance as EXEC, but the fd came from the daemon instead of `forkpty()`.

```c
typedef struct {
    // ...existing fields...
    ghostty_surface_io_e io_mode;  // EXEC (default), MANUAL, or EXTERNAL_FD
    int io_fd;                      // pre-existing PTY master fd (for EXTERNAL_FD mode)
} ghostty_surface_config_s;
```

### Resize and Divider Drag

Ghostty handles resize natively: `setFrameSize` → `ghostty_surface_set_size` → `ioctl(TIOCSWINSZ)` → shell gets SIGWINCH.

**Divider drag concern:** every drag frame changes the frame, triggering SIGWINCH. At 120Hz, TUI apps receive 120 SIGWINCH/sec and attempt to redraw each time — a redraw storm.

**Solution:** Add `ghostty_surface_set_resize_paused(surface, bool)` to GhosttyKit. During divider drag:
1. `ghostty_surface_set_resize_paused(surface, true)` — Ghostty processes `set_size` for rendering (Metal redraws at new dimensions) but does NOT call `ioctl(TIOCSWINSZ)`.
2. On drag end: `ghostty_surface_set_resize_paused(surface, false)` — Ghostty sends one final SIGWINCH at the settled size.

This replaces the current `suppressPaneResize` flag at the correct abstraction level.

### forged (Forge Daemon)

A minimal process (~400 lines) bundled inside Forge.app:

- **Socket**: `$TMPDIR/forge-daemon.sock` (per-user, survives within boot session, cleaned on reboot)
- **Protocol**: JSON control messages + fd passing via `sendmsg(SCM_RIGHTS)`. Protocol includes a version field for forward compatibility.
- **Operations**:
  - `{"op": "store", "pane_id": "...", "metadata": {...}}` + fd via ancillary data
  - `{"op": "retrieve", "pane_id": "..."}` → daemon sends fd back via ancillary data
  - `{"op": "list"}` → returns all stored panes with metadata (cwd, pid, alive status)
  - `{"op": "release", "pane_id": "..."}` → daemon closes the fd, process gets SIGHUP
- **Lifecycle**: launched by Forge on first run via `posix_spawn`, stays alive after Forge exits. Later: launchd plist with `KeepAlive` for crash resilience.
- **State**: in-memory fd table + metadata. No disk persistence — the fds ARE the state.
- **Ownership**: one Forge instance at a time. Second instance detects existing socket → shows error dialog: "Forge is already running. Force take over?" Force take over sends a `shutdown` command to the existing daemon connection, then reconnects.

### fd Lifecycle (Ordering Matters)

**Creating a pane:**
1. Ghostty surface created (EXEC mode) → `forkpty()` → shell starts (async on Termio thread)
2. Ghostty delivers `GHOSTTY_ACTION_CHILD_STARTED` via `action_cb` with the child PID — this signals the fd is ready
3. Forge calls `ghostty_surface_pty_fd(surface)` to get the master fd. **Forge must NOT read/write/close this fd** — it is borrowed solely for `sendmsg` to the daemon.
4. Forge sends fd to daemon via `sendmsg` → daemon holds a `dup`. This happens in the `action_cb` handler, minimizing the race window.
5. Normal operation: Ghostty reads/writes fd, daemon holds idle dup

**Closing a pane (intentional):**
1. Forge sends `release` to daemon → daemon closes its dup
2. Forge destroys Ghostty surface → Ghostty closes its fd → SIGHUP → process dies

**Forge quits (persistence):**
1. `applicationShouldTerminate` returns `.terminateLater` (blocks quit)
2. Forge synchronously dumps scrollback for each surface (Ghostty terminal state access) — surfaces must still be alive
3. Forge saves workspace.json (including window frame, split ratios, active selections)
4. Forge calls `NSApp.reply(toApplicationShouldTerminate: true)` → app terminates
5. Ghostty surfaces destroyed → Ghostty closes its fds
6. Daemon's dups keep PTYs alive → processes keep running

**Forge crashes (unclean exit):**
1. Forge exits without sending fds — but daemon ALREADY has dups (from step 4 of creation)
2. Scrollback dump didn't happen → reconnect shows blank until SIGWINCH redraw
3. workspace.json may be stale → daemon's `list` is authoritative for which panes exist

**Forge reconnects:**
1. Read workspace.json for project/tab structure
2. Connect to daemon → `list` → get alive pane IDs
3. Reconcile: workspace.json structure + daemon's alive panes
4. For each alive pane: `retrieve` fd → create Ghostty surface (EXTERNAL_FD mode)
5. Set the surface size to match the SwiftUI frame BEFORE attaching the fd (ensures grid matches)
6. Feed saved scrollback (if available) into surface for visual continuity
7. Send `SIGWINCH` to PTY → shell/TUI redraws at current size. Note: SIGWINCH is best-effort — some processes may not redraw until the next user keystroke. This is a known limitation.
8. Dead panes: show "[Process exited]" with option to close or restart

### Scrollback Persistence

On clean quit, before surfaces are destroyed:
1. For each pane, access Ghostty's terminal screen state
2. Serialize the visible screen + scrollback to `~/.config/forge/scrollback/<pane-id>`
3. On reconnect, feed this content into the new surface before connecting the live fd

This provides visual continuity: the user sees their previous terminal content immediately, then live output resumes on top of it.

For crash recovery (no scrollback dump): surfaces start blank, but SIGWINCH causes shells to redraw their prompt. TUI apps (vim, htop) redraw their full UI. The gap is shell history/scrollback, which is lost.

### Workspace Persistence

Saved to `~/.config/forge/workspace.json` on every structural change (add/remove/rename project/tab/pane, split ratio change, active selection change). Written continuously, not just on quit — so crash-staleness is minimal (at most the last few seconds of changes):

```json
{
  "version": 1,
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
          "splitTree": { "direction": "horizontal", "ratio": 0.5 }
        }
      ]
    }
  ],
  "activeProjectId": "uuid-1",
  "activeTabId": "uuid-2",
  "windowFrame": { "x": 100, "y": 100, "width": 1400, "height": 900 }
}
```

Includes window frame, active selection, and per-tab split trees with ratios.

### Attention System

Event-driven replacements for tmux's poll-based detection:

| Current (tmux) | New (native) |
|---|---|
| `%bell` control mode event | `GHOSTTY_ACTION_BELL` via `action_cb` |
| Silence subscription (`window_silence_flag`) | Track last output timestamp per surface. Ghostty's read callback provides the timing. |
| `capture-pane` content scanning (5s poll) | Ghostty's VT output hook — scan content as it arrives (zero latency) |
| `pane_current_command` from tmux query | `GHOSTTY_ACTION_COMMAND_FINISHED` via `action_cb` |
| `pane_current_path` from tmux query | `proc_pidinfo(PROC_PIDVNODEPATHINFO)` on the child PID |

### Working Directory Tracking

Currently from tmux's `pane_current_path`. Replaced by:
```swift
func currentWorkingDirectory(pid: pid_t) -> String? {
    var pathInfo = proc_vnodepathinfo()
    let size = MemoryLayout<proc_vnodepathinfo>.size
    let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &pathInfo, Int32(size))
    guard ret == size else { return nil }
    return String(cString: &pathInfo.pvi_cdir.vip_path.0)
}
```

Used for: title bar path display, "new tab in same directory" feature, workspace.json persistence.

### Input Handling

**Deleted entirely.** No more `sendKeyEvent()`, `performKeyEquivalent` bypass, `send-keys` encoding, key name mapping, hex encoding, literal quoting.

Ghostty's native key handling takes over. In EXEC mode, Ghostty negotiates terminal capabilities with the shell via the PTY. If the shell requests Kitty keyboard protocol, Ghostty uses it. Otherwise, legacy encoding. This is automatic — no configuration needed.

**Validation step for Phase 1:** verify that Ghostty's default key encoding works correctly with zsh, bash, and Claude Code by testing Ctrl+C, Ctrl+D, Ctrl+Z, arrow keys, and space.

### Split Pane Orchestration

Without tmux, Forge owns split creation and removal:

**Creating a split:**
1. User triggers "Split Right" or "Split Down" from menu/shortcut
2. WorkspaceController updates the domain model: inserts a new `Pane` into `Tab.panes`, updates `Tab.splitTree` (adds a new split node with 0.5 ratio)
3. SwiftUI re-renders `PaneSplitView` with the updated tree → new `PaneTerminalView` appears
4. The new view triggers Ghostty surface creation (via `ProcessPort.create`)
5. Ghostty forks the shell → surface starts rendering → `action_cb` delivers child PID → fd sent to daemon
6. The new pane's frame is determined by SwiftUI layout (the 0.5 ratio split) — Ghostty gets its size from `setFrameSize`, not from the create call

**Removing a pane (exit or close):**
1. Process exits → `GHOSTTY_ACTION_CHILD_EXITED` via `action_cb`
2. WorkspaceController updates the domain model: removes the `Pane`, collapses the `SplitNode` tree (if a split has only one child remaining, replace it with that child)
3. `ProcessPort.kill()` releases daemon fd and destroys surface
4. SwiftUI re-renders → surviving pane expands to fill the space
5. Surviving pane's `setFrameSize` fires → Ghostty resizes → shell gets SIGWINCH

**Key difference from tmux:** tmux handled split topology internally (layout engine, resize redistribution). Now Forge's domain model (`SplitNode` tree) and SwiftUI's layout system handle it. The split tree is just data — SwiftUI does the pixel math.

### Shell Environment

New panes inherit from a defined environment:
- `TERM`: set by Ghostty (typically `xterm-ghostty`)
- `SHELL`: user's login shell (from `passwd`)
- `HOME`, `USER`, `PATH`: inherited from Forge's process environment
- `COLORTERM=truecolor`: set by Ghostty
- `LANG`, `LC_*`: inherited from system

New tabs/splits in the same project: inherit the project's `path` as initial `cwd`. Environment is NOT inherited from sibling panes (each pane is a fresh shell invocation, same as opening a new Terminal.app tab).

## What Gets Deleted

| File | Lines | Why |
|---|---|---|
| TmuxAdapter.swift | ~250 | Replaced by ProcessAdapter |
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
| WC+Rendering resize/input logic | ~180 | Ghostty handles both |
| **Total** | **~1620 lines + 2MB binary** | |

## What Gets Added

| Component | Lines | Purpose |
|---|---|---|
| forged daemon | ~400 | fd vault for persistence |
| ProcessAdapter | ~100 | ProcessPort (create/reconnect/kill via GhosttyKit) |
| DaemonAdapter | ~150 | PersistencePort (Unix socket + fd passing) |
| WorkspacePersistence | ~150 | JSON save/load + scrollback dump/restore |
| GhosttyKit EXTERNAL_FD mode | ~50 | Accept pre-existing PTY fd (Zig) |
| GhosttyKit resize_paused API | ~20 | Suppress SIGWINCH during drag |
| GhosttyKit pty_fd + child_pid accessors | ~15 | Get master fd for daemon, child PID for CWD tracking |
| action_cb implementation | ~80 | Bell, child exit, command done, clipboard, title |
| CWD tracker | ~30 | proc_pidinfo for working directory |
| **Total** | **~990 lines** | |

Net: **-630 lines, -2MB binary, and every rendering bug eliminated.**

## Migration Plan

### Phase 0: Prerequisites (in current tmux codebase)

- Implement `action_cb` dispatch in GhosttyApp (bell, child exit, command finished, clipboard read, title, cell size)
- Verify Ghostty EXEC mode key encoding works with zsh/bash/Claude Code
- Add `ghostty_surface_set_resize_paused` API to GhosttyKit fork
- Add `ghostty_surface_pty_fd` accessor to GhosttyKit fork
- Add `ghostty_surface_child_pid` accessor to GhosttyKit fork (for CWD tracking via proc_pidinfo)
- Add EXTERNAL_FD io mode to GhosttyKit fork
- Add `GHOSTTY_ACTION_CHILD_STARTED` action (signals fd is ready after async fork)
- These are all additive — no existing behavior changes

### Phase 1: Native PTY mode (opt-in, no persistence)

- Feature flag: `nativePTY` in ForgeConfig (default false)
- Create ProcessAdapter using GhosttyKit EXEC mode
- When flag is on: new panes use ProcessPort instead of TmuxPort
- Remove input bypass from GhosttyNSView (let Ghostty handle keys)
- Wire action_cb events to AttentionManager
- Wire resize_paused in PaneSplitView divider drag
- Add CWD tracking via proc_pidinfo
- tmux code path remains for flag=false (no deletions yet)
- **Quit warning**: "Quitting will end all terminal sessions" (Phase 1 only)
- **Result**: TUI apps work perfectly, all rendering bugs gone. No persistence.

### Phase 2: forged daemon + persistence

- Build forged binary (bundled in Forge.app)
- Create DaemonAdapter implementing PersistencePort
- On pane creation: get fd from Ghostty, send dup to daemon
- On quit: dump scrollback, save workspace.json, exit cleanly
- On crash: daemon already has fds (sent at creation time)
- On reconnect: retrieve fds, create EXTERNAL_FD surfaces, restore scrollback, SIGWINCH
- Add workspace.json persistence (projects, tabs, panes, splits, window frame)
- Remove quit warning (persistence works)
- **Result**: full persistence, tmux-equivalent UX

### Phase 3: Cleanup

- Remove all tmux infrastructure files (~1620 lines)
- Remove bundled tmux binary from Makefile
- Remove feature flag — native PTY is the only mode
- Update CONTEXT.md, CLAUDE.md, domain glossary
- Delete TmuxPort protocols from Core/Ports
- Add ProcessPort + PersistencePort to Core/Ports
- **Result**: clean codebase, no tmux dependency

## Risks

| Risk | Mitigation |
|---|---|
| GhosttyKit changes (EXTERNAL_FD, resize_paused, pty_fd) | We own the fork. Changes are small and additive. |
| Daemon crash kills processes | launchd KeepAlive plist. Daemon is ~400 lines — small failure surface. |
| Scrollback lost on Forge crash | Accepted for v1. Shells redraw on SIGWINCH. TUI apps redraw fully. Only shell history is lost. |
| Concurrent Forge instances | Daemon socket has single-owner semantics. Second instance shows error or takes over. |
| fd exhaustion with many panes | Call `setrlimit(RLIMIT_NOFILE)` at daemon startup. Default 256 is low; raise to 10240. |
| Shell env differs from tmux | Documented in "Shell Environment" section. TERM is `xterm-ghostty` instead of `tmux-256color`. Most tools handle both. |
| No remote/SSH session sharing | Out of scope. Forge is a local app. tmux-mode can be re-added later as optional. |

## Error States

| Scenario | UX |
|---|---|
| Daemon socket missing on launch | Toast: "Starting forge daemon..." Auto-launch daemon. Retry connection. |
| Daemon running but no fds (all processes died) | Show empty workspace. Toast: "Previous sessions ended." |
| workspace.json exists but daemon has different panes | Reconcile: daemon's `list` is authoritative for which panes are alive. Dead panes removed from model. |
| Daemon crashes mid-session | Terminals keep working (Ghostty holds its own fd copies). Toast: "Daemon lost — restarting..." Auto-relaunch daemon, re-send fds. What's lost: persistence safety net. If Forge ALSO quits before daemon recovers, processes die. |
| Forge crashes mid-session | On next launch: daemon has fds, workspace.json may be stale. Reconcile and reconnect. Scrollback lost (no dump). |
