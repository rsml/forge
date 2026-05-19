import Testing
import Foundation
@testable import ForgeCore

@Suite("BrowserActivityResolver")
@MainActor
struct BrowserActivityResolverTests {

    // MARK: - Fixtures

    /// Build a workspace with one project, one tab, and the given panes.
    private func workspaceWith(panes: [Pane]) -> Workspace {
        let ws = Workspace()
        let project = Project(id: "p", name: "proj", attached: true)
        let tab = Tab(id: "t", projectId: "p", index: 0, name: "tab")
        for pane in panes { tab.panes.append(pane) }
        project.tabs.append(tab)
        ws.projects.append(project)
        return ws
    }

    private func terminal(_ id: String) -> Pane {
        Pane(id: id, tabId: "t", index: 0)
    }

    private func browser(_ id: String, url: URL?, title: String = "") -> Pane {
        let p = Pane.browser(id: id, tabId: "t", url: url)
        if let state = p.browserState { state.pageTitle = title }
        return p
    }

    // MARK: - partition

    @Test("terminal-only panes go to the terminal list")
    func partitionTerminalsOnly() {
        let ws = workspaceWith(panes: [terminal("t1"), terminal("t2")])
        let (browsers, terminalIds) = BrowserActivityResolver.partition(
            paneIds: ["t1", "t2"], workspace: ws
        )
        #expect(browsers.isEmpty)
        #expect(terminalIds == ["t1", "t2"])
    }

    @Test("browser pane with URL counts as active")
    func browserWithURLIsActive() {
        let ws = workspaceWith(panes: [
            browser("b1", url: URL(string: "https://github.com/anthropics")!)
        ])
        let (browsers, terminalIds) = BrowserActivityResolver.partition(
            paneIds: ["b1"], workspace: ws
        )
        #expect(terminalIds.isEmpty)
        #expect(browsers.count == 1)
        #expect(browsers[0].isActive == true)
        #expect(browsers[0].command == "github.com")
    }

    @Test("browser pane prefers page title over host")
    func browserPrefersTitle() {
        let ws = workspaceWith(panes: [
            browser("b1",
                    url: URL(string: "https://github.com/anthropics/claude-code")!,
                    title: "GitHub - claude-code")
        ])
        let (browsers, _) = BrowserActivityResolver.partition(
            paneIds: ["b1"], workspace: ws
        )
        #expect(browsers[0].command == "GitHub - claude-code")
    }

    @Test("whitespace-only title falls back to host (with non-default port)")
    func browserWhitespaceTitleFallsBack() {
        let ws = workspaceWith(panes: [
            browser("b1",
                    url: URL(string: "http://localhost:3000")!,
                    title: "  \n")
        ])
        let (browsers, _) = BrowserActivityResolver.partition(
            paneIds: ["b1"], workspace: ws
        )
        #expect(browsers[0].command == "localhost:3000")
    }

    @Test("URL with no host falls back to absoluteString")
    func browserNoHostFallsBack() {
        let url = URL(string: "about:blank")!
        let ws = workspaceWith(panes: [browser("b1", url: url)])
        let (browsers, _) = BrowserActivityResolver.partition(
            paneIds: ["b1"], workspace: ws
        )
        #expect(browsers[0].command == "about:blank")
    }

    @Test("browser pane with no URL is idle")
    func browserNoURLIsIdle() {
        let ws = workspaceWith(panes: [browser("b1", url: nil)])
        let (browsers, _) = BrowserActivityResolver.partition(
            paneIds: ["b1"], workspace: ws
        )
        #expect(browsers.count == 1)
        #expect(browsers[0].isActive == false)
        #expect(browsers[0].command == nil)
    }

    @Test("mixed browser + terminal partitions correctly")
    func mixedPartition() {
        let ws = workspaceWith(panes: [
            terminal("t1"),
            browser("b1", url: URL(string: "https://example.com")!),
            terminal("t2")
        ])
        let (browsers, terminalIds) = BrowserActivityResolver.partition(
            paneIds: ["t1", "b1", "t2"], workspace: ws
        )
        #expect(browsers.count == 1)
        #expect(browsers[0].paneId == "b1")
        #expect(terminalIds == ["t1", "t2"])
    }

    @Test("unknown pane IDs go to the terminal list (fail-open)")
    func unknownIdsToTerminalList() {
        let ws = workspaceWith(panes: [terminal("t1")])
        let (browsers, terminalIds) = BrowserActivityResolver.partition(
            paneIds: ["t1", "ghost"], workspace: ws
        )
        #expect(browsers.isEmpty)
        #expect(terminalIds == ["t1", "ghost"])
    }

    @Test("nil workspace punts everything to the terminal list")
    func nilWorkspace() {
        let (browsers, terminalIds) = BrowserActivityResolver.partition(
            paneIds: ["a", "b"], workspace: nil
        )
        #expect(browsers.isEmpty)
        #expect(terminalIds == ["a", "b"])
    }

    // MARK: - displayName (direct)

    @Test("displayName: title wins over host")
    func displayNameTitle() {
        let url = URL(string: "https://github.com/foo")!
        #expect(BrowserActivityResolver.displayName(title: "Hello", url: url) == "Hello")
    }

    @Test("displayName: empty title falls back to host")
    func displayNameEmptyTitle() {
        let url = URL(string: "https://github.com/foo")!
        #expect(BrowserActivityResolver.displayName(title: "", url: url) == "github.com")
    }

    // MARK: - hostAndPort (port inclusion)

    @Test("hostAndPort: includes non-default http port")
    func hostAndPortNonDefaultHTTP() {
        let url = URL(string: "http://localhost:3000/foo")!
        #expect(BrowserActivityResolver.hostAndPort(url) == "localhost:3000")
    }

    @Test("hostAndPort: omits default http port (80)")
    func hostAndPortDefaultHTTP() {
        // URL(string:) doesn't surface an explicit port when it equals the
        // scheme default, so this exercises the "no port" branch too.
        let url = URL(string: "http://localhost/")!
        #expect(BrowserActivityResolver.hostAndPort(url) == "localhost")
    }

    @Test("hostAndPort: omits default https port (443)")
    func hostAndPortDefaultHTTPS() {
        let url = URL(string: "https://example.com/")!
        #expect(BrowserActivityResolver.hostAndPort(url) == "example.com")
    }

    @Test("hostAndPort: includes non-default https port")
    func hostAndPortNonDefaultHTTPS() {
        let url = URL(string: "https://example.com:8443/")!
        #expect(BrowserActivityResolver.hostAndPort(url) == "example.com:8443")
    }

    @Test("hostAndPort: returns nil for URL with no host")
    func hostAndPortNoHost() {
        let url = URL(string: "about:blank")!
        #expect(BrowserActivityResolver.hostAndPort(url) == nil)
    }

    @Test("hostAndPort: includes explicit port 80 when scheme isn't http")
    func hostAndPortExplicit80OnOtherScheme() {
        // Unknown scheme has no default port; any explicit port should appear.
        let url = URL(string: "ws://example.com:80/")!
        #expect(BrowserActivityResolver.hostAndPort(url) == "example.com:80")
    }
}
