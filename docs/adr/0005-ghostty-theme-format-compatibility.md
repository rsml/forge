# 0005: Ghostty Theme Format Compatibility

**Status:** accepted
**Date:** 2026-05-18

## Context

Forge renders terminal cells via libghostty (GhosttyKit.xcframework). Theme colors are passed to libghostty as Ghostty config strings (`background=#hex`, `foreground=#hex`, `palette=N=#hex`, `cursor-color=#hex`). User-facing themes are sourced from the `mbadolato/iTerm2-Color-Schemes` repo, which publishes themes in Ghostty's grammar in its `ghostty/` subdirectory.

Forge is moving from reading themes off the user's Ghostty install to bundling a curated catalog inside the .app. The open question: should Forge define its own theme grammar — with room for extensions like selection colors, cursor accent, per-pane overrides, or semantic colors — or stay compatible with Ghostty's existing format?

## Decision

Forge themes stay Ghostty-format-compatible. The recognized keys are exactly: `background`, `foreground`, `palette=N=#hex` for `N` in `0..15`, and `cursor-color`. Forge does not extend the format.

Themes are stored as text files in `Resources/themes/*.conf` (bundled) and `~/.config/forge/themes/*.conf` (user override).

## Consequences

- **Good**: Themes are zero-conversion portable between Forge, Ghostty, iTerm2, Alacritty, WezTerm, and Kitty — users can re-use existing themes and share theirs across terminals without reformatting.
- **Good**: The import script can copy upstream files verbatim, adding only an attribution header — no per-theme conversion logic to maintain.
- **Bad**: If Forge later wants selection bg/fg, cursor accent, per-pane overrides, or semantic colors (warning/success), we either fork the format (creating Forge-only themes that no longer round-trip) or push the feature upstream into Ghostty.
- **Bad**: We inherit Ghostty's expressiveness limits — for example, no programmable color computation and no theme composition.

Revisit if Forge needs theme features Ghostty doesn't support, or if a stable cross-terminal theme spec emerges.
