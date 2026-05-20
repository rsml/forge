import Foundation

/// Decides whether a pane's current foreground process should drive the
/// "waiting for input" indicator using output-silence as a signal.
///
/// Rationale: claude/codex/aider/opencode all sit silent at a prompt between
/// turns. Their UIs don't emit a steady stream of bytes when idle (no spinner,
/// no progress). A long pause in output, while a known AI agent is foreground,
/// is a reliable proxy for "the user's turn now" — even when the agent
/// declines to emit an OSC 777 notify (which Claude Code only does for
/// out-of-focus terminals).
///
/// Non-agent foreground processes (vim, less, top, npm run dev, sleep, …) are
/// explicitly excluded: the user owns the wait, no dot.
public enum AttentionPolicy {
    /// Lower-cased foreground process basenames whose silence indicates
    /// "waiting for the user". Update as new AI CLIs ship.
    public static let aiAgentNames: Set<String> = [
        "claude", "codex", "aider", "opencode", "gemini", "amp",
        "cursor", "windsurf", "ai"
    ]

    public static func isAIAgent(_ command: String) -> Bool {
        aiAgentNames.contains(command.lowercased())
    }

    /// How long the foreground AI agent must be silent before we treat the
    /// pane as waiting for user input.
    public static let silenceWaitingThreshold: TimeInterval = 1.5
}
