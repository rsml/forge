import Foundation
import Testing
@testable import ForgeDomain

// Tests for notification/bell event system
@Suite("Bell Event Handling")
@MainActor
struct BellEventHandlingTests {

    @Test("Bell state propagation through tab hierarchy")
    func testBellStatePropagation() {
        // Create test data structure
        let pane = Pane(id: "pane1", tabId: "window1")
        let tab = Tab(id: "window1", projectId: "session1", index: 0, name: "test")
        tab.panes = [pane]

        // Initially should not need attention
        #expect(tab.needsAttention == false)

        // Set bell on pane
        pane.hasBell = true

        // Tab should now need attention
        #expect(tab.needsAttention == true)
        #expect(pane.needsAttention == true)
    }

    @Test("Clearing bell state")
    func testClearingBellState() {
        let pane = Pane(id: "pane1", tabId: "window1")
        let tab = Tab(id: "window1", projectId: "session1", index: 0, name: "test")
        tab.panes = [pane]

        // Set bell
        pane.hasBell = true
        #expect(tab.needsAttention == true)

        // Clear bell
        pane.hasBell = false
        #expect(tab.needsAttention == false)
    }

    @Test("Multiple panes bell state")
    func testMultiplePanesBellState() {
        let pane1 = Pane(id: "pane1", tabId: "window1")
        let pane2 = Pane(id: "pane2", tabId: "window1")
        let tab = Tab(id: "window1", projectId: "session1", index: 0, name: "test")
        tab.panes = [pane1, pane2]

        // Set bell on one pane
        pane1.hasBell = true
        #expect(tab.needsAttention == true)

        // Clear that pane's bell
        pane1.hasBell = false
        #expect(tab.needsAttention == false)

        // Set bell on second pane
        pane2.hasBell = true
        #expect(tab.needsAttention == true)
    }

    @Test("Project attention propagation")
    func testSessionAttentionPropagation() {
        let pane = Pane(id: "pane1", tabId: "window1")
        let tab = Tab(id: "window1", projectId: "session1", index: 0, name: "test")
        tab.panes = [pane]

        let project = Project(id: "session1", name: "test-project")
        project.tabs = [tab]

        // Initially should not need attention
        #expect(project.needsAttention == false)

        // Set bell on pane
        pane.hasBell = true

        // Project should propagate the attention
        #expect(project.needsAttention == true)
    }
}
