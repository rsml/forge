import Foundation
import Testing
@testable import ForgeCore

@Suite("ContentDetector")
struct ContentDetectorTests {

    @MainActor private var patterns: [String] { ContentDetector.defaultPatterns }

    // MARK: - Exact string match

    @MainActor
    @Test("exact string match returns true")
    func testExactStringMatch() {
        let detector = ContentDetector()
        let result = detector.scan(paneId: "%1", content: "Allow once", patterns: patterns)
        #expect(result == true)
    }

    // MARK: - Regex match

    @MainActor
    @Test("regex pattern match returns true")
    func testRegexMatch() {
        let detector = ContentDetector()
        let result = detector.scan(paneId: "%1", content: "Overwrite file? [y/N]", patterns: patterns)
        #expect(result == true)
    }

    // MARK: - No match

    @MainActor
    @Test("no match returns false")
    func testNoMatch() {
        let detector = ContentDetector()
        let result = detector.scan(paneId: "%1", content: "$ ls -la\ntotal 42", patterns: patterns)
        #expect(result == false)
    }

    // MARK: - Dedup

    @MainActor
    @Test("same content on second scan returns false (dedup)")
    func testDedup() {
        let detector = ContentDetector()
        let content = "Allow once"
        let first = detector.scan(paneId: "%1", content: content, patterns: patterns)
        let second = detector.scan(paneId: "%1", content: content, patterns: patterns)
        #expect(first == true)
        #expect(second == false)
    }

    // MARK: - Reset after content changes

    @MainActor
    @Test("content changes clears state, next match fires again")
    func testResetAfterChange() {
        let detector = ContentDetector()
        let first = detector.scan(paneId: "%1", content: "Allow once", patterns: patterns)
        #expect(first == true)

        // User responded — content no longer matches
        let cleared = detector.scan(paneId: "%1", content: "$ ", patterns: patterns)
        #expect(cleared == false)
        #expect(detector.isActive(paneId: "%1") == false)

        // New prompt appears — should fire again
        let second = detector.scan(paneId: "%1", content: "Do you want to continue?", patterns: patterns)
        #expect(second == true)
    }

    // MARK: - isActive

    @MainActor
    @Test("isActive reflects current state")
    func testIsActive() {
        let detector = ContentDetector()
        #expect(detector.isActive(paneId: "%1") == false)

        _ = detector.scan(paneId: "%1", content: "Allow once", patterns: patterns)
        #expect(detector.isActive(paneId: "%1") == true)

        _ = detector.scan(paneId: "%1", content: "$ ", patterns: patterns)
        #expect(detector.isActive(paneId: "%1") == false)
    }

    // MARK: - paneRemoved

    @MainActor
    @Test("paneRemoved clears state")
    func testPaneRemoved() {
        let detector = ContentDetector()
        _ = detector.scan(paneId: "%1", content: "Allow once", patterns: patterns)
        #expect(detector.isActive(paneId: "%1") == true)

        detector.paneRemoved("%1")
        #expect(detector.isActive(paneId: "%1") == false)
    }

    // MARK: - Independent panes

    @MainActor
    @Test("different panes track independently")
    func testIndependentPanes() {
        let detector = ContentDetector()
        let first = detector.scan(paneId: "%1", content: "Allow once", patterns: patterns)
        let second = detector.scan(paneId: "%2", content: "Allow once", patterns: patterns)
        #expect(first == true)
        #expect(second == true)

        // Dedup applies per-pane
        let repeat1 = detector.scan(paneId: "%1", content: "Allow once", patterns: patterns)
        #expect(repeat1 == false)
    }

    // MARK: - Custom patterns

    @MainActor
    @Test("custom patterns work alongside defaults")
    func testCustomPatterns() {
        let detector = ContentDetector()
        let custom = ["Press Enter to continue"]
        let result = detector.scan(
            paneId: "%1",
            content: "Press Enter to continue",
            patterns: patterns + custom
        )
        #expect(result == true)
    }
}
