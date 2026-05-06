import Foundation
import Testing
@testable import ForgeDomain

@Suite("TmuxEventParser")
struct TmuxEventParserTests {

    @Test("parses bell event with tab ID")
    func parseBell() {
        let event = TmuxEventParser.parse("%bell @5")
        #expect(event == .bell(tabId: "@5"))
    }

    @Test("ignores bell event without tab ID")
    func parseBellNoId() {
        let event = TmuxEventParser.parse("%bell")
        #expect(event == .ignored)
    }

    @Test("parses tab-close event")
    func parseTabClose() {
        let event = TmuxEventParser.parse("%tab-close @3")
        #expect(event == .tabClose(tabId: "@3"))
    }

    @Test("parses unlinked-tab-close event")
    func parseUnlinkedTabClose() {
        let event = TmuxEventParser.parse("%unlinked-tab-close @7")
        #expect(event == .tabClose(tabId: "@7"))
    }

    @Test("parses structural events")
    func parseStructural() {
        let cases = ["%tab-add @1", "%layout-change @2 abc", "%project-changed $1",
                     "%project-renamed $2", "%tab-renamed @3"]
        for raw in cases {
            #expect(TmuxEventParser.parse(raw) == .structural, "Expected structural for: \(raw)")
        }
    }

    @Test("ignores informational events")
    func parseIgnored() {
        let cases = ["%begin 123", "%end 456", "%error foo", "%pane-mode-changed %1", "%output %1 hello"]
        for raw in cases {
            #expect(TmuxEventParser.parse(raw) == .ignored, "Expected ignored for: \(raw)")
        }
    }
}
