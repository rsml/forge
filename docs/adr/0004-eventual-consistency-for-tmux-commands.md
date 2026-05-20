# 0004: Eventual Consistency for Tmux Commands

**Status:** superseded — tmux integration has been removed; Forge now uses libghostty + a `forged` PTY-fd daemon. Retained as historical record.
**Date:** 2026-05-06

## Context

Forge communicates with tmux through two channels:

1. **TmuxCommandRunner** — synchronous request-response (`tmux list-sessions`, `tmux new-session`, etc.). Returns output or nil on failure.
2. **TmuxControlMode** — fire-and-forget stdin writes to a `tmux -CC attach` process. Commands go to stdin with no per-command acknowledgement. State changes arrive as push events (`%session-changed`, `%window-add`, etc.).

This is a CQRS pattern: commands (control mode writes) and queries (runner commands, refresh cycle) travel different paths. Most mutations (kill, rename, move, split) use control mode because it avoids process-spawn overhead and races with the persistent connection.

The question: how should we handle errors for control mode commands that have no response?

## Decision

The **refresh cycle** (TmuxSyncEngine) is the consistency mechanism for fire-and-forget commands. We do not fake synchronous error handling for control mode writes.

Specifically:

- **Request-response calls** (`TmuxCommandRunner.run()`): propagate failure to the caller. `newProject()` returns `Bool`; callers show a toast on failure.
- **Control mode commands**: fire-and-forget. The next refresh cycle (triggered by the resulting tmux event, or by the 5-second poll) will merge the authoritative tmux state into the domain model, correcting any divergence.
- **Optimistic UI updates**: permitted only for drag interactions (reorder, swap) where latency matters. All other mutations wait for the refresh cycle.
- **Connection health**: TmuxControlMode tracks disconnect/reconnect and surfaces a toast so the user knows when commands may be dropped.

## Consequences

- **Good**: Honest error model. No false confidence from wrapping fire-and-forget in `throws`. Simpler adapter code.
- **Good**: Drag interactions remain responsive (optimistic updates for reorder/swap).
- **Good**: Disconnect toast gives users visibility into connection health.
- **Bad**: Mutations that silently fail (e.g., `kill-session` on a session that's already gone) won't surface an error — they'll just be corrected by the next refresh. This is acceptable because the end state is correct.
- **Bad**: There's a brief window (up to 150ms debounce + query time) where the UI may show stale state after a control mode command.
