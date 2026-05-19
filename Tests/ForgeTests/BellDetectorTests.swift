import Testing
import Foundation
@testable import ForgeCore

struct BellDetectorTests {
    @Test("a standalone BEL byte is detected")
    func testStandaloneBel() {
        let data = Data([0x07])
        #expect(BellDetector.containsStandaloneBell(data) == true)
    }

    @Test("BEL inside OSC 133 prompt marker is ignored")
    func testOSC133Ignored() {
        // ESC ] 1 3 3 ; A BEL — what zsh emits on each prompt redraw
        let data = Data([0x1B, 0x5D, 0x31, 0x33, 0x33, 0x3B, 0x41, 0x07])
        #expect(BellDetector.containsStandaloneBell(data) == false)
    }

    @Test("BEL inside OSC followed by real BEL after is detected")
    func testOSCThenStandalone() {
        // OSC marker ending in BEL, then literal BEL
        let data = Data([0x1B, 0x5D, 0x30, 0x3B, 0x68, 0x69, 0x07,  // OSC 0;hi BEL (set title)
                         0x07])                                       // standalone BEL
        #expect(BellDetector.containsStandaloneBell(data) == true)
    }

    @Test("OSC ending in ESC \\ does not consume a later real BEL")
    func testOSCWithStTerminatorThenBell() {
        // OSC 0;X ESC \ then BEL
        let data = Data([0x1B, 0x5D, 0x30, 0x3B, 0x58, 0x1B, 0x5C, 0x07])
        #expect(BellDetector.containsStandaloneBell(data) == true)
    }

    @Test("no BEL means no detection")
    func testNoBel() {
        let data = Data("hello world\n".utf8)
        #expect(BellDetector.containsStandaloneBell(data) == false)
    }

    @Test("regression: bash $TITLE escape with embedded BEL terminator")
    func testTitleEscape() {
        // ESC ] 0 ; t i t l e BEL
        let data = Data([0x1B, 0x5D, 0x30, 0x3B, 0x74, 0x69, 0x74, 0x6C, 0x65, 0x07])
        #expect(BellDetector.containsStandaloneBell(data) == false)
    }
}
