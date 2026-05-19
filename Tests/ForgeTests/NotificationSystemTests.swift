import Foundation
import Testing
@testable import ForgeCore

// Tests for notification/bell event system
@Suite("Bell Event Handling")
@MainActor
struct BellEventHandlingTests {

    @Test("Bell state propagation through tab hierarchy")
    func testBellStatePropagation() {
        // Create test data structure
        let pane = Pane(id: "pane1", tabId: "window1", currentCommand: "claude")
        let tab = Tab(id: "window1", projectId: "session1", index: 0, name: "test")
        tab.panes = [pane]

        // Initially should not need attention
        #expect(tab.needsAttention == false)

        // Set bell on pane
        pane.terminalState!.hasBell = true

        // Tab should now need attention
        #expect(tab.needsAttention == true)
        #expect(pane.needsAttention == true)
    }

    @Test("Clearing bell state")
    func testClearingBellState() {
        let pane = Pane(id: "pane1", tabId: "window1", currentCommand: "claude")
        let tab = Tab(id: "window1", projectId: "session1", index: 0, name: "test")
        tab.panes = [pane]

        // Set bell
        pane.terminalState!.hasBell = true
        #expect(tab.needsAttention == true)

        // Clear bell
        pane.terminalState!.hasBell = false
        #expect(tab.needsAttention == false)
    }

    @Test("Multiple panes bell state")
    func testMultiplePanesBellState() {
        let pane1 = Pane(id: "pane1", tabId: "window1", currentCommand: "claude")
        let pane2 = Pane(id: "pane2", tabId: "window1", currentCommand: "claude")
        let tab = Tab(id: "window1", projectId: "session1", index: 0, name: "test")
        tab.panes = [pane1, pane2]

        // Set bell on one pane
        pane1.terminalState!.hasBell = true
        #expect(tab.needsAttention == true)

        // Clear that pane's bell
        pane1.terminalState!.hasBell = false
        #expect(tab.needsAttention == false)

        // Set bell on second pane
        pane2.terminalState!.hasBell = true
        #expect(tab.needsAttention == true)
    }

    @Test("Project attention propagation")
    func testSessionAttentionPropagation() {
        let pane = Pane(id: "pane1", tabId: "window1", currentCommand: "claude")
        let tab = Tab(id: "window1", projectId: "session1", index: 0, name: "test")
        tab.panes = [pane]

        let project = Project(id: "session1", name: "test-project")
        project.tabs = [tab]

        // Initially should not need attention
        #expect(project.needsAttention == false)

        // Set bell on pane
        pane.terminalState!.hasBell = true

        // Project should propagate the attention
        #expect(project.needsAttention == true)
    }
}
