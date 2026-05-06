# 0002: AttentionManager Lives in App Layer

**Status:** accepted (known violation — should migrate to Adapters/)
**Date:** 2026-05-06

## Context

`AttentionManager` implements `AttentionPort` (defined in `Domain/Ports/`). The hexagonal rule is: port implementations live in `Adapters/`. However, `AttentionManager` was placed in `App/` because it wires together multiple concerns: it owns an `AttentionQueue` (domain), calls `NotificationPort.send()` (adapter), reads config from `ForgeConfigStore` (adapter), and is injected into views via `@Environment`.

## Decision

`AttentionManager` lives in `Sources/App/` despite implementing a domain port. This was a pragmatic choice during initial development — it needed access to both the notification adapter and the config store, and placing it in App made wiring simpler.

## Consequences

**Good:**
- Simple wiring in `AppDelegate` — all dependencies are right there.
- Easy to inject into SwiftUI views via `@Environment`.

**Bad:**
- Violates the architectural rule that port implementations belong in `Adapters/`.
- Couples `AttentionManager` to `ForgeConfigStore.shared` directly instead of injecting config.
- Sets a precedent that port implementations can live anywhere.

**Migration path:** Move to `Sources/Adapters/Attention/AttentionManager.swift`. Inject config persistence via a closure or small protocol instead of importing `ForgeConfigStore` directly. The `@Environment` injection in `AppDelegate` doesn't need to change — only the file location and import.
