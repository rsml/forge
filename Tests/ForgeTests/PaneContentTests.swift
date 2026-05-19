import Testing
import Foundation
@testable import ForgeCore

@MainActor
struct PaneContentTests {
    @Test("terminal pane exposes terminalState, not browserState")
    func testTerminalAccessor() {
        let pane = Pane(id: "p1", tabId: "t1", currentCommand: "zsh")
        #expect(pane.terminalState != nil)
        #expect(pane.browserState == nil)
        #expect(pane.kind == .terminal)
    }

    @Test("browser pane exposes browserState, not terminalState")
    func testBrowserAccessor() {
        let url = URL(string: "https://localhost:3000")!
        let pane = Pane.browser(id: "p2", tabId: "t1", url: url)
        #expect(pane.terminalState == nil)
        #expect(pane.browserState != nil)
        #expect(pane.browserState?.url?.absoluteString == "https://localhost:3000")
        #expect(pane.kind == .browser)
    }

    @Test("browser pane never needsAttention")
    func testBrowserNeverAttention() {
        let pane = Pane.browser(id: "p3", tabId: "t1", url: nil)
        #expect(pane.needsAttention == false)
    }

    @Test("BrowserState defaults to nil URL and empty title")
    func testBrowserStateDefaults() {
        let s = BrowserState()
        #expect(s.url == nil)
        #expect(s.pageTitle == "")
        #expect(s.canGoBack == false)
        #expect(s.canGoForward == false)
        #expect(s.isLoading == false)
        #expect(s.loadingProgress == 0.0)
        #expect(s.faviconData == nil)
    }
}
