import XCTest
@testable import TmuxControl

final class TmuxLayoutTests: XCTestCase {
    func testOffLeavesGeometryUnchanged() {
        let tree = parse("c195,80x24,0,0[80x12,0,0,0,80x11,0,13,1]")
        tree.adjustForPaneBorderStatus(.off)
        assertLeaf(tree, pane: 0, width: 80, height: 12, x: 0, y: 0)
        assertLeaf(tree, pane: 1, width: 80, height: 11, x: 0, y: 13)
    }

    func testSingleTop() {
        let tree = parse("d1fd,164x49,0,0,0")
        tree.adjustForPaneBorderStatus(.top)
        assertLeaf(tree, pane: 0, width: 164, height: 48, x: 0, y: 1)
    }

    func testSingleBottom() {
        let tree = parse("d1fd,164x49,0,0,0")
        tree.adjustForPaneBorderStatus(.bottom)
        assertLeaf(tree, pane: 0, width: 164, height: 48, x: 0, y: 0)
    }

    func testHSplitTop() {
        let tree = parse("8205,80x24,0,0{40x24,0,0,0,39x24,41,0,1}")
        tree.adjustForPaneBorderStatus(.top)
        assertLeaf(tree, pane: 0, width: 40, height: 23, x: 0, y: 1)
        assertLeaf(tree, pane: 1, width: 39, height: 23, x: 41, y: 1)
    }

    func testEmptyFloatingLayout() {
        XCTAssertTrue(TmuxLayoutParser.layoutHasNoTiledPanes("abcd,"))
        XCTAssertTrue(TmuxLayoutParser.layoutHasNoTiledPanes(""))
        XCTAssertFalse(TmuxLayoutParser.layoutHasNoTiledPanes("d1fd,164x49,0,0,0"))
    }

    func testJSONSinglePane() {
        let layout = #"{"V":2,"L":{"t":"p","w":80,"h":24,"x":0,"y":0,"a":true,"i":0,"I":"%7"}}"#
        let tree = TmuxLayoutParser.parsedLayout(from: layout)
        XCTAssertNotNil(tree)
        XCTAssertEqual(tree?.type, .vSplit)
        XCTAssertEqual(tree?.children.count, 1)
        XCTAssertEqual(tree?.children.first?.windowPane, 7)
        XCTAssertEqual(tree?.children.first?.width, 80)
    }

    func testJSONMixedSplitsTiledAndFloating() {
        let mixed = #"{"V":2,"L":{"t":"h","w":120,"h":40,"x":0,"y":0,"c":[{"t":"p","w":60,"h":40,"x":0,"y":0,"l":3,"i":0,"I":"%0"},{"t":"v","w":59,"h":40,"x":61,"y":0,"c":[{"t":"p","w":59,"h":20,"x":61,"y":0,"l":2,"i":1,"I":"%1"},{"t":"p","w":59,"h":19,"x":61,"y":21,"l":1,"i":2,"I":"%2"},{"t":"p","w":60,"h":10,"x":4,"y":2,"l":0,"i":3,"z":1,"I":"%3"},{"t":"p","w":60,"h":10,"x":8,"y":4,"a":true,"i":4,"z":0,"I":"%4"}]}]}}"#
        let tree = TmuxLayoutParser.parsedLayout(from: mixed)
        XCTAssertEqual(tree?.type, .vSplit)
        XCTAssertEqual(tree?.width, 120)
        XCTAssertEqual(tree?.height, 40)
        XCTAssertEqual(tree?.floatingPanes.count, 2)
        XCTAssertEqual(Set(tree?.floatingPanes.compactMap(\.windowPane) ?? []), [3, 4])
        XCTAssertEqual(tree?.windowPanes().sorted(), [0, 1, 2, 3, 4])
    }

    private func parse(_ layout: String) -> TmuxLayoutNode {
        guard let tree = TmuxLayoutParser.parsedLayout(from: layout) else {
            XCTFail("Failed to parse \(layout)")
            return TmuxLayoutNode(type: .leaf)
        }
        return tree
    }

    private func assertLeaf(_ tree: TmuxLayoutNode, pane: Int, width: Int, height: Int, x: Int, y: Int) {
        guard let leaf = tree.leaf(forPane: pane) else {
            XCTFail("No leaf for pane \(pane)")
            return
        }
        XCTAssertEqual(leaf.width, width, "pane \(pane) width")
        XCTAssertEqual(leaf.height, height, "pane \(pane) height")
        XCTAssertEqual(leaf.x, x, "pane \(pane) x")
        XCTAssertEqual(leaf.y, y, "pane \(pane) y")
    }
}
