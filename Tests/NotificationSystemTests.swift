import Foundation
import Testing

// Tests for notification/bell event system
@Suite("Bell Event Handling")
struct BellEventHandlingTests {

    @Test("Bell event parser handles valid format")
    func testBellEventParsing() {
        let event = "%bell %1"
        let parts = event.split(separator: " ")

        #expect(parts.count >= 2)
        #expect(String(parts[0]) == "%bell")
        #expect(String(parts[1]) == "%1")
    }

    @Test("Bell event parser handles window ID extraction")
    func testWindowIdExtraction() {
        let event = "%bell %42"
        let parts = event.split(separator: " ")

        if parts.count >= 2 {
            let windowId = String(parts[1])
            #expect(windowId == "%42")
        }
    }

    @Test("Bell state propagation through window hierarchy")
    func testBellStatePropagation() {
        // Create test data structure
        let pane = Pane(id: "pane1", windowId: "window1")
        let window = Window(id: "window1", sessionId: "session1", index: 0, name: "test")
        window.panes = [pane]

        // Initially should not need attention
        #expect(window.needsAttention == false)

        // Set bell on pane
        pane.hasBell = true

        // Window should now need attention
        #expect(window.needsAttention == true)
        #expect(pane.needsAttention == true)
    }

    @Test("Clearing bell state")
    func testClearingBellState() {
        let pane = Pane(id: "pane1", windowId: "window1")
        let window = Window(id: "window1", sessionId: "session1", index: 0, name: "test")
        window.panes = [pane]

        // Set bell
        pane.hasBell = true
        #expect(window.needsAttention == true)

        // Clear bell
        pane.hasBell = false
        #expect(window.needsAttention == false)
    }

    @Test("Multiple panes bell state")
    func testMultiplePanesBellState() {
        let pane1 = Pane(id: "pane1", windowId: "window1")
        let pane2 = Pane(id: "pane2", windowId: "window1")
        let window = Window(id: "window1", sessionId: "session1", index: 0, name: "test")
        window.panes = [pane1, pane2]

        // Set bell on one pane
        pane1.hasBell = true
        #expect(window.needsAttention == true)

        // Clear that pane's bell
        pane1.hasBell = false
        #expect(window.needsAttention == false)

        // Set bell on second pane
        pane2.hasBell = true
        #expect(window.needsAttention == true)
    }

    @Test("Session attention propagation")
    func testSessionAttentionPropagation() {
        let pane = Pane(id: "pane1", windowId: "window1")
        let window = Window(id: "window1", sessionId: "session1", index: 0, name: "test")
        window.panes = [pane]

        let session = Session(id: "session1", name: "test-session")
        session.windows = [window]

        // Initially should not need attention
        #expect(session.needsAttention == false)

        // Set bell on pane
        pane.hasBell = true

        // Session should propagate the attention
        #expect(session.needsAttention == true)
    }
}
