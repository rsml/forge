# Native PTY Architecture — Phase 2: forged Daemon

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add process persistence across Forge restarts via a lightweight fd-holding daemon (`forged`). When Forge quits, processes keep running. When it reopens, terminals reconnect.

**Architecture:** `forged` is a minimal daemon (~400 lines) that holds PTY master fd duplicates via Unix domain sockets with `sendmsg(SCM_RIGHTS)`. During normal operation it's idle (not in the data path). On Forge quit, the daemon's fd copies keep PTYs alive. On reconnect, fds are sent back to Forge.

**Spec:** `docs/superpowers/specs/2026-05-16-native-pty-architecture-design.md` (sections: forged, fd Lifecycle, Scrollback Persistence, Workspace Persistence)

**Depends on:** Phase 1 (native PTY mode) — must be working with `nativePTY: true`

---

## Components

### New Files
- `Sources/Daemon/forged.swift` — the daemon binary (standalone executable)
- `Sources/Daemon/FDSocket.swift` — Unix socket helpers for fd passing
- `Sources/Infrastructure/Process/DaemonAdapter.swift` — PersistencePort implementation (client side)
- `Sources/Infrastructure/Process/WorkspacePersistence.swift` — JSON save/load for workspace structure

### Modified Files
- `Package.swift` — add `forged` executable target
- `Makefile` — build and bundle forged inside Forge.app
- `Sources/ForgeApp.swift` — launch daemon on startup, wire quit flow
- `Sources/WorkspaceController.swift` — connect to daemon, reconnect flow
- `Sources/WorkspaceController+Rendering.swift` — EXTERNAL_FD surface creation for reconnect
- `Sources/Infrastructure/Terminal/GhosttyRenderer.swift` — EXTERNAL_FD initializer
- `vendor/ghostty/include/ghostty.h` — add EXTERNAL_FD io mode enum
- `vendor/ghostty/src/apprt/embedded.zig` — implement EXTERNAL_FD in Termio

---

## Tasks

### Task 1: Unix socket fd-passing helpers

Create `Sources/Daemon/FDSocket.swift` with:
- `FDSocket.send(fd: Int32, over socket: Int32, message: Data)` — sends a file descriptor via `sendmsg` with `SCM_RIGHTS`
- `FDSocket.receive(from socket: Int32) -> (fd: Int32, message: Data)?` — receives an fd via `recvmsg`
- `FDSocket.listen(path: String) -> Int32` — create and bind a Unix domain socket
- `FDSocket.connect(path: String) -> Int32?` — connect to an existing socket

### Task 2: forged daemon binary

Create `Sources/Daemon/forged.swift`:
- Parse command line: `forged --socket <path>`
- Listen on Unix domain socket
- Accept connections, handle JSON protocol:
  - `store` + fd → hold in dictionary
  - `retrieve` → send fd back
  - `list` → return all stored panes
  - `release` → close fd
  - `shutdown` → clean exit
- Main run loop with `select()`/`poll()`
- Log to `/tmp/forged.log`

### Task 3: DaemonAdapter (client side)

Create `Sources/Infrastructure/Process/DaemonAdapter.swift`:
- Implements `PersistencePort` protocol
- Connects to daemon socket
- Sends store/retrieve/list/release commands
- Handles fd passing via FDSocket helpers

### Task 4: Add EXTERNAL_FD io mode to GhosttyKit

Modify `vendor/ghostty/include/ghostty.h`:
- Add `GHOSTTY_SURFACE_IO_EXTERNAL_FD = 2` to `ghostty_surface_io_mode_e`
- Add `int io_fd` field to `ghostty_surface_config_s`

Modify Zig source to handle the new mode:
- In `src/apprt/embedded.zig`: when io_mode is EXTERNAL_FD, use the provided fd instead of forkpty()

### Task 5: EXTERNAL_FD GhosttyRenderer initializer

Add `init(ghosttyApp:fd:)` to GhosttyRenderer:
- Uses `GHOSTTY_SURFACE_IO_EXTERNAL_FD` with the daemon-provided fd
- Deferred surface connection (same as EXEC mode)
- Send SIGWINCH after connection to force shell redraw

### Task 6: Workspace persistence (JSON)

Create `Sources/Infrastructure/Process/WorkspacePersistence.swift`:
- Save workspace structure to `~/.config/forge/workspace.json`
- Load on startup
- Includes: projects, tabs, panes (with IDs, cwds), split trees, window frame, active selections

### Task 7: Wire daemon into Forge lifecycle

Modify `ForgeApp.swift` and `WorkspaceController.swift`:
- On startup: launch daemon (if not running), connect
- On pane creation: send fd to daemon
- On quit: `applicationShouldTerminate(.terminateLater)` → dump scrollback → save workspace → reply terminate
- On reconnect: read workspace.json → retrieve fds from daemon → create EXTERNAL_FD surfaces → SIGWINCH

### Task 8: Scrollback dump/restore

- On quit: for each surface, access Ghostty terminal state, serialize to `~/.config/forge/scrollback/<pane-id>`
- On reconnect: feed saved scrollback into new surface before connecting live fd

### Task 9: Integration testing

- Start Forge with nativePTY → create project → type commands
- Quit Forge → verify daemon holds fds → processes still running
- Reopen Forge → verify terminals reconnect with content
- Kill daemon → verify Forge handles gracefully
