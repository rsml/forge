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
        // Equatable ignores proportions — topology check only
        #expect(node == .split(.horizontal, [.leaf, .leaf], proportions: []))
    }

    @Test("vertical split returns two children")
    func verticalSplit() {
        let node = LayoutParser.parse("ab12,190x50,0,0[190x25,0,0,1,190x24,0,26,2]")
        #expect(node == .split(.vertical, [.leaf, .leaf], proportions: []))
    }

    @Test("nested splits")
    func nestedSplits() {
        let nested: SplitNode = .split(.vertical, [.leaf, .leaf], proportions: [])
        let expected: SplitNode = .split(.horizontal, [.leaf, nested], proportions: [])
        let node = LayoutParser.parse("ab12,190x50,0,0{95x50,0,0,1,95x50,96,0[47x25,0,0,2,47x24,0,26,3]}")
        #expect(node == expected)
    }

    @Test("three-way horizontal split")
    func threeWayHorizontal() {
        let expected: SplitNode = .split(.horizontal, [.leaf, .leaf, .leaf], proportions: [])
        let node = LayoutParser.parse("ab12,270x50,0,0{90x50,0,0,1,90x50,91,0,2,90x50,182,0,3}")
        #expect(node == expected)
    }

    @Test("leaf count matches pane count")
    func leafCount() {
        let node = LayoutParser.parse("ab12,190x50,0,0{95x50,0,0,1,95x50,96,0[47x25,0,0,2,47x24,0,26,3]}")
        #expect(node.leafCount == 3)
    }

    // MARK: - Proportion Tests

    @Test("horizontal split proportions from unequal widths")
    func unequalHorizontalProportions() {
        // 66-wide left, 65-wide right → ~50.4% / ~49.6%
        let node = LayoutParser.parse("ab12,132x20,0,0{66x20,0,0,1,65x20,67,0,2}")
        if case .split(_, _, let proportions) = node {
            #expect(proportions.count == 2)
            #expect(abs(proportions[0] - 66.0 / 131.0) < 0.001)
            #expect(abs(proportions[1] - 65.0 / 131.0) < 0.001)
        } else {
            Issue.record("Expected split node")
        }
    }

    @Test("vertical split proportions from unequal heights")
    func unequalVerticalProportions() {
        // 19-tall top, 20-tall bottom → ~48.7% / ~51.3%
        let node = LayoutParser.parse("ab12,132x40,0,0[132x19,0,0,1,132x20,0,20,2]")
        if case .split(_, _, let proportions) = node {
            #expect(proportions.count == 2)
            #expect(abs(proportions[0] - 19.0 / 39.0) < 0.001)
            #expect(abs(proportions[1] - 20.0 / 39.0) < 0.001)
        } else {
            Issue.record("Expected split node")
        }
    }

    @Test("real-world nested layout proportions")
    func realWorldLayout() {
        // From actual tmux: top pane 19 rows, bottom split into 66+65 columns at 20 rows
        let node = LayoutParser.parse("b362,132x40,0,0[132x19,0,0,29,132x20,0,20{66x20,0,20,31,65x20,67,20,33}]")
        if case .split(.vertical, let children, let proportions) = node {
            #expect(children.count == 2)
            #expect(abs(proportions[0] - 19.0 / 39.0) < 0.001)
            if case .split(.horizontal, _, let innerProportions) = children[1] {
                #expect(abs(innerProportions[0] - 66.0 / 131.0) < 0.001)
            } else {
                Issue.record("Expected inner horizontal split")
            }
        } else {
            Issue.record("Expected outer vertical split")
        }
    }
}
