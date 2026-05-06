# 0003: Unified Command Dispatch via AppCommand + AppState

**Status:** accepted
**Date:** 2026-05-06

## Context

The codebase had three dispatch mechanisms for user-initiated actions: NotificationCenter posts (15 app-specific notification names), direct controller method calls, and closure callbacks. The same class of operation (e.g., "toggle sidebar") could use any of the three depending on where it was triggered. This made command flow hard to trace, provided no type safety, and created inconsistency that new features would inherit.

## Decision

Replace all user-command notifications with a typed `AppCommand` enum and an observable `AppState` object:

- **`AppCommand`** (in `Core/`) — Pure enum listing every user-initiated action that crosses view boundaries. No framework imports.
- **`AppState`** (in `Features/Shared/`) — `@Observable` object owning shared UI state (active modal, sidebar visibility, expanded projects, inline rename state). Has a single `dispatch(_ command:)` method that translates commands into state transitions or delegates domain operations to `WorkspaceController`.
- **Views** bind directly to `AppState` properties via `@Environment`. No `.onReceive(NotificationCenter...)`.
- **Senders** (menu commands, command palette, toolbar buttons) call `appState.dispatch(.commandName)`.

Two infrastructure signals remain on NotificationCenter: `.forgeWindowTitleChanged` and `.forgeConfigChanged`. These are system events (not user commands) and stay as broadcast notifications.

## Consequences

**Good:**
- One dispatch mechanism for all user commands. Type-safe, grep-able, traceable.
- UI state that was scattered across `@State` in individual views is now centralized and observable.
- Commands are testable: given state X, dispatch command Y, verify state Z.
- New features add a case to `AppCommand` — the compiler enforces exhaustive handling.

**Bad:**
- `AppState.dispatch()` is a large switch statement that will grow with new commands. If it exceeds 300 lines, split into per-category handler methods.
- Stack dismiss actions use a `pendingStackAction` state property to preserve the dismiss animation, which is slightly less direct than the old notification → view handler path.
