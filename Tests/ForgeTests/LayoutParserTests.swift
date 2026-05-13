import Testing
@testable import ForgeCore

@Suite("LayoutParser")
struct LayoutParserTests {

    @Test("single pane returns a leaf")
    func singlePane() {
        let node = LayoutParser.parse("ab12,190x50,0,0,1")
        #expect(node == .leaf)
    }

    @Test("horizontal split returns two children")
    func horizontalSplit() {
        let node = LayoutParser.parse("ab12,190x50,0,0{95x50,0,0,1,95x50,96,0,2}")
        #expect(node == .split(.horizontal, [.leaf, .leaf]))
    }

    @Test("vertical split returns two children")
    func verticalSplit() {
        let node = LayoutParser.parse("ab12,190x50,0,0[190x25,0,0,1,190x24,0,26,2]")
        #expect(node == .split(.vertical, [.leaf, .leaf]))
    }

    @Test("nested splits")
    func nestedSplits() {
        let node = LayoutParser.parse("ab12,190x50,0,0{95x50,0,0,1,95x50,96,0[47x25,0,0,2,47x24,0,26,3]}")
        #expect(node == .split(.horizontal, [.leaf, .split(.vertical, [.leaf, .leaf])]))
    }

    @Test("three-way horizontal split")
    func threeWayHorizontal() {
        let node = LayoutParser.parse("ab12,270x50,0,0{90x50,0,0,1,90x50,91,0,2,90x50,182,0,3}")
        #expect(node == .split(.horizontal, [.leaf, .leaf, .leaf]))
    }

    @Test("leaf count matches pane count")
    func leafCount() {
        let node = LayoutParser.parse("ab12,190x50,0,0{95x50,0,0,1,95x50,96,0[47x25,0,0,2,47x24,0,26,3]}")
        #expect(node.leafCount == 3)
    }
}
