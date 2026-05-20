import Testing
import Foundation
@testable import ForgeCore

struct AttentionPolicyTests {
    @Test("claude is recognized as an AI agent")
    func testClaude() {
        #expect(AttentionPolicy.isAIAgent("claude") == true)
    }

    @Test("name match is case-insensitive")
    func testCaseInsensitive() {
        #expect(AttentionPolicy.isAIAgent("CLAUDE") == true)
        #expect(AttentionPolicy.isAIAgent("Codex") == true)
    }

    @Test("non-agent commands are excluded — user owns the wait")
    func testNonAgents() {
        #expect(AttentionPolicy.isAIAgent("vim") == false)
        #expect(AttentionPolicy.isAIAgent("sleep") == false)
        #expect(AttentionPolicy.isAIAgent("npm") == false)
        #expect(AttentionPolicy.isAIAgent("docker") == false)
        #expect(AttentionPolicy.isAIAgent("") == false)
        #expect(AttentionPolicy.isAIAgent("zsh") == false)
    }
}

@MainActor
struct SilentWaitingNeedsAttentionTests {
    @Test("isSilentWaiting alone is enough to need attention")
    func testIsSilentWaitingTriggersAttention() {
        let pane = Pane(id: "p", tabId: "t", currentCommand: "claude")
        pane.terminalState?.status = .running
        #expect(pane.needsAttention == false)

        pane.terminalState?.isSilentWaiting = true
        #expect(pane.needsAttention == true)
    }

    @Test("clearing isSilentWaiting drops needsAttention back to false")
    func testClearingDrops() {
        let pane = Pane(id: "p", tabId: "t", currentCommand: "claude")
        pane.terminalState?.status = .running
        pane.terminalState?.isSilentWaiting = true
        #expect(pane.needsAttention == true)

        pane.terminalState?.isSilentWaiting = false
        #expect(pane.needsAttention == false)
    }
}
