# 0002: AttentionManager Lives in Features/Attention

**Status:** resolved
**Date:** 2026-05-06 (updated 2026-05-06)

## Context

`AttentionManager` implements `AttentionPort` (defined in `Core/Ports/`). The original hexagonal rule was "port implementations live in Adapters." However, AttentionManager wires together multiple concerns: it owns an `AttentionQueue` (domain), calls `NotificationPort.send()` (adapter), reads config from `ForgeConfigStore`, and is injected into views via `@Environment`.

## Decision

`AttentionManager` lives in `Sources/Features/Attention/`. Under the feature-based architecture adopted in the folder migration, feature-specific adapters live inside the feature. `MacNotificationAdapter` (which implements `NotificationPort`) also lives in `Features/Attention/`.

## Resolution

The original concerns have been addressed:
- **Location:** Moved from `App/` to `Features/Attention/` — correct per the feature-based architecture rules.
- **Config coupling:** `ForgeConfigStore` is now constructor-injected, not accessed via `.shared`.
- **Content scanning:** `AttentionManager` now owns `ContentDetector` and content scanning, registered as a post-refresh hook on `TmuxSyncEngine`. This makes it a proper vertical slice owning all attention-related concerns.

No further migration needed.
