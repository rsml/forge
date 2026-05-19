# Forge Domain Glossary

Terms used consistently across code, docs, and conversation. If a term isn't here, don't invent one — ask.

## Core Model

**Workspace** — The root container. One per app instance. Holds all projects and tracks which project/tab/pane is active. Persisted to `workspace.json`.

**Project** — A top-level item in the sidebar. Has a name, an optional filesystem path, and an ordered list of tabs.

**Tab** — An item nested inside a project. Has a name, an index, and one or more panes plus an optional split tree.

**Pane** — A terminal instance inside a tab. Backed by a PTY whose master fd is held by the `forged` daemon (so the shell survives Forge restarts) and a libghostty surface for rendering. Has a status (idle/running) and attention flags (bell, content match).

**SplitNode** — Tree of pane splits within a Tab. Leaves correspond to panes in `Tab.panes` order; internal nodes carry direction and child proportions.

## Attention System

**Attention** — A pane (and by extension its tab) needs the user's notice. Triggered by BEL bytes, content pattern matches, or command completion. Visualized as a dot in the sidebar and drives the stack mode queue.

**AttentionQueue** — A FIFO queue of tab UUIDs that need attention. Owned by `AttentionManager`. Supports priority operations: promote to front, move to back, hide.

**Bell** — A `0x07` (BEL) byte in a pane's PTY output. Sets `pane.hasBell = true`. The most common attention trigger.

**Content Match** — A regex or exact-string match against recent PTY output. Used to detect interactive prompts (e.g., "y/N", "Allow once"). Deduplicated per pane — fires once until content changes.

**Command Completion** — Detected when a pane's foreground process transitions from active to idle (long-running task finished, back at the shell). Surfaced via `PaneActivityPort` polling.

## View Modes

**List Mode** — The default. Sidebar visible, tab bar at top, split buttons in title bar. User navigates by selecting projects and tabs.

**Stack Mode** — Sidebar hidden. The attention queue drives what's shown. The frontmost queued tab is displayed full-screen with a toolbar for Done/Hide/Move to Back. Designed for monitoring multiple concurrent tasks.

## Ports

**Port** — A protocol in `Core/Ports/` defining a capability the domain needs but doesn't implement. Adapters provide concrete implementations.

- **AttentionPort** — Attention queue management.
- **NotificationPort** — System and in-app notification delivery.
- **PaneActivityPort** — Foreground-process activity check (`query(paneIds:)`). Used by close-confirmation and command-completion detection. Fail-open under timeout.
- **ProcessPort / PersistencePort** — Pane creation and PTY-fd persistence. `DaemonAdapter` implements `PersistencePort`.

## Infrastructure

**forged** — Sidecar daemon (bundled in `Forge.app/Contents/MacOS/forged`) that holds PTY master fds across Forge launches via a Unix-domain socket. Operations: `store`, `retrieve`, `list`, `release`, `is_active`. The daemon's fd dups keep shells alive even when Forge quits — Forge uses `_exit(0)` to bypass AppKit teardown that would otherwise close the fds and SIGHUP the children.

**GhosttyKit** — Vendored `xcframework` built from `vendor/ghostty` (rsml/ghostty fork). Provides the libghostty C API for terminal surface rendering. Two modes used: `EXEC` (Ghostty forks the shell and owns the PTY) and `EXTERNAL_FD` (Forge passes in a PTY fd retrieved from the daemon for reconnect).

**workspace.json** — Persisted workspace structure (projects, tabs, panes, split trees). Loaded on startup, saved on changes. Together with daemon-held PTYs, this lets a Forge restart fully restore the previous session.
