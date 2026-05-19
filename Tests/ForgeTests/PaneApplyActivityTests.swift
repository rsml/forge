import Testing
import Foundation
@testable import ForgeCore

@MainActor
struct PaneApplyActivityTests {
    @Test("applyActivity updates currentCommand and re-derives status for a non-shell command")
    func testApplyClaudeMakesRunning() {
        let pane = Pane(id: "p1", tabId: "t1", currentCommand: "")
        #expect(pane.terminalState?.status == .idle)
        #expect(pane.needsAttention == true)

        pane.apply(activity: PaneActivity(paneId: "p1", isActive: true, command: "claude"))

        #expect(pane.terminalState?.currentCommand == "claude")
        #expect(pane.terminalState?.status == .running)
        #expect(pane.needsAttention == false)
    }

    @Test("applyActivity reverts to idle when daemon reports no foreground process")
    func testApplyNilGoesIdle() {
        let pane = Pane(id: "p1", tabId: "t1", currentCommand: "claude")
        pane.terminalState?.status = .running
        #expect(pane.needsAttention == false)

        pane.apply(activity: PaneActivity(paneId: "p1", isActive: false, command: nil))

        #expect(pane.terminalState?.currentCommand == "")
        #expect(pane.terminalState?.status == .idle)
        #expect(pane.needsAttention == true)
    }
}
