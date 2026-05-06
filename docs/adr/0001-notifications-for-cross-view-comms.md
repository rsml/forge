# 0001: Notifications for Cross-View Communication

**Status:** superseded by [0003](0003-unified-command-dispatch.md)
**Date:** 2026-05-06

## Context

SwiftUI views that need to trigger actions in unrelated views (e.g., menu bar "Toggle Sidebar" affecting MainView, or "Command Palette" opening a modal) have no natural parent-child data flow path. Passing closures or bindings through many layers of view hierarchy creates tight coupling and prop drilling.

## Decision

Use `NotificationCenter.default.post(name:)` with app-specific notification names (`.forgeToggleSidebar`, `.forgeCommandPalette`, etc.) for fire-and-forget cross-view signals. Views subscribe via `.onReceive` or `NotificationCenter.addObserver`.

## Consequences

**Good:**
- Zero coupling between sender and receiver. Menu commands, keyboard shortcuts, and command palette all use the same mechanism.
- Easy to add new triggers without modifying existing views.

**Bad:**
- No request/response — the sender doesn't know if anything handled the notification.
- Hard to trace: grep for `.forgeNewProject` doesn't show the complete flow in one place.
- Mixes with other dispatch mechanisms (direct controller method calls, closure callbacks) — the codebase now has three ways to trigger the same class of action. This is the primary friction point.
- No type safety on notification payloads.

**Superseded:** Replaced by `AppCommand` enum + `AppState` observable dispatch in ADR-0003.
