# Forge Domain Glossary

Terms used consistently across code, docs, and conversation. If a term isn't here, don't invent one — ask.

## Core Model

**Workspace** — The root container. One per app instance. Holds all projects and tracks which project/tab/pane is active. Not persisted; rebuilt from tmux state on connect.

**Project** — A top-level item in the sidebar. Backed by a tmux session. Has a name, an optional filesystem path, and an ordered list of tabs. "Session" only appears in tmux adapter command strings.

**Tab** — An item nested inside a project. Backed by a tmux window. Has a name, an index, and one or more panes. "Window" only appears in tmux adapter command strings.

**Pane** — A terminal instance inside a tab. Backed by a tmux pane. Has a status (idle/running), and attention flags (bell, content match). Rendered by SwiftTerm.

## Attention System

**Attention** — A pane (and by extension its tab) needs the user's notice. Triggered by bell events, content pattern matches, or command completion. Visualized as a dot in the sidebar and drives the stack mode queue.

**AttentionQueue** — A FIFO queue of tab UUIDs that need attention. Owned by `AttentionManager`. Supports priority operations: promote to front, move to back, hide.

**Bell** — A tmux `%bell` event on a pane. Sets `pane.hasBell = true`. The most common attention trigger.

**Content Match** — A regex or exact-string match against the last N lines of a running pane's output. Used to detect interactive prompts (e.g., "y/N", "Allow once"). Deduplicated per pane — fires once until content changes.

**Command Completion** — Detected when a pane transitions from running to idle (the command's process exited). Fires an attention event so the user knows a long-running task finished.

## View Modes

**List Mode** — The default. Sidebar visible, tab bar at top, split buttons in title bar. User navigates by selecting projects and tabs.

**Stack Mode** — Sidebar hidden. The attention queue drives what's shown. The frontmost queued tab is displayed full-screen with a toolbar for Done/Hide/Move to Back. Designed for monitoring multiple concurrent tasks.

## Ports

**Port** — A protocol in `Domain/Ports/` defining a capability the domain needs but doesn't implement. Adapters provide concrete implementations.

- **TmuxPort** — All tmux operations: list/create/kill projects and tabs, capture pane content, control mode lifecycle.
- **GitPort** — Git queries (currently just `currentBranch`).
- **AttentionPort** — Attention queue management and notification dispatch.
- **NotificationPort** — System and in-app notification delivery.

## Infrastructure

**Control Mode** — Tmux's `-CC` flag. Produces a stream of structured events (`%begin`, `%end`, `%output`, `%session-changed`, etc.) on stdout. Forge uses this for push-based state updates instead of polling.

**Forge Socket** — The isolated tmux socket (`-L forge`). Separates Forge's tmux server from the user's normal tmux sessions.

**Refresh** — A full state sync: query tmux for all projects/tabs/panes, merge into the workspace model via `StateMerger`, scan for content matches. Triggered by control mode events (debounced) and a 5-second periodic timer.
