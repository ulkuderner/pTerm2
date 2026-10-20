import Foundation

/// Node kinds in a tmux window layout. Values match the macOS `LayoutNodeType`
/// so fixtures and tests stay comparable.
public enum TmuxLayoutNodeType: Int, Sendable {
    case leaf = 0
    case hSplit = 1
    case vSplit = 2
}

/// Value of tmux’s per-window `pane-border-status` option.
public enum TmuxPaneBorderStatus: Sendable {
    case off
    case top
    case bottom

    public static func from(string: String?) -> TmuxPaneBorderStatus {
        switch string {
        case "top":
            return .top
        case "bottom":
            return .bottom
        default:
            return .off
        }
    }
}

public struct TmuxLayoutLeaf: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var x: Int
    public var y: Int
    public var windowPane: Int?
    public var zIndex: Int?

    public init(width: Int, height: Int, x: Int, y: Int, windowPane: Int?, zIndex: Int? = nil) {
        self.width = width
        self.height = height
        self.x = x
        self.y = y
        self.windowPane = windowPane
        self.zIndex = zIndex
    }
}

public final class TmuxLayoutNode: Equatable, @unchecked Sendable {
    public var type: TmuxLayoutNodeType
    public var width: Int?
    public var height: Int?
    public var x: Int?
    public var y: Int?
    public var windowPane: Int?
    public var zIndex: Int?
    public var children: [TmuxLayoutNode]
    public var floatingPanes: [TmuxLayoutNode]

    public init(type: TmuxLayoutNodeType,
                width: Int? = nil,
                height: Int? = nil,
                x: Int? = nil,
                y: Int? = nil,
                windowPane: Int? = nil,
                zIndex: Int? = nil,
                children: [TmuxLayoutNode] = [],
                floatingPanes: [TmuxLayoutNode] = []) {
        self.type = type
        self.width = width
        self.height = height
        self.x = x
        self.y = y
        self.windowPane = windowPane
        self.zIndex = zIndex
        self.children = children
        self.floatingPanes = floatingPanes
    }

    public static func == (lhs: TmuxLayoutNode, rhs: TmuxLayoutNode) -> Bool {
        return lhs.type == rhs.type
            && lhs.width == rhs.width
            && lhs.height == rhs.height
            && lhs.x == rhs.x
            && lhs.y == rhs.y
            && lhs.windowPane == rhs.windowPane
            && lhs.zIndex == rhs.zIndex
            && lhs.children == rhs.children
            && lhs.floatingPanes == rhs.floatingPanes
    }

    public var isLeaf: Bool { type == .leaf }

    public func leaf(forPane pane: Int) -> TmuxLayoutNode? {
        if type == .leaf, windowPane == pane {
            return self
        }
        for child in children {
            if let found = child.leaf(forPane: pane) {
                return found
            }
        }
        for floating in floatingPanes {
            if floating.windowPane == pane {
                return floating
            }
        }
        return nil
    }

    public func windowPanes() -> [Int] {
        if type == .leaf {
            if let windowPane {
                return [windowPane]
            }
            return []
        }
        var result: [Int] = []
        for child in children {
            result.append(contentsOf: child.windowPanes())
        }
        for floating in floatingPanes {
            if let windowPane = floating.windowPane {
                result.append(windowPane)
            }
        }
        return result
    }

    public func adjustForPaneBorderStatus(_ status: TmuxPaneBorderStatus) {
        guard status != .off, let windowHeight = height, windowHeight > 0 else {
            return
        }
        adjustLeaves(status: status, windowHeight: windowHeight)
    }

    private func adjustLeaves(status: TmuxPaneBorderStatus, windowHeight: Int) {
        if type != .leaf {
            for child in children {
                child.adjustLeaves(status: status, windowHeight: windowHeight)
            }
            return
        }
        guard let yoff = y, let leafHeight = height, leafHeight > 1 else {
            return
        }
        switch status {
        case .off:
            break
        case .top:
            if yoff == 0 {
                y = yoff + 1
                height = leafHeight - 1
            }
        case .bottom:
            if yoff + leafHeight == windowHeight {
                height = leafHeight - 1
            }
        }
    }
}

public enum TmuxLayoutParser {
    /// tmux 3.8 and later send an empty layout for a window whose panes are all
    /// floating to a client that has not opted in to the new layout format.
    public static func layoutHasNoTiledPanes(_ layout: String) -> Bool {
        return matches(layout, pattern: "^([0-9a-fA-F]{4},)?$")
    }

    public static func parsedLayout(from layout: String) -> TmuxLayoutNode? {
        if TmuxJSONLayoutParser.isJSONLayout(layout) {
            guard let tree = TmuxJSONLayoutParser.parsedLayout(from: layout) else {
                return nil
            }
            return coalesced(tree)
        }
        return parsedV1Layout(from: layout)
    }

    private static func parsedV1Layout(from layout: String) -> TmuxLayoutNode? {
        if layout.count <= 5 {
            return nil
        }
        var working = layout
        var floats: [TmuxLayoutNode]?
        if let floatsStart = working.firstIndex(of: "<") {
            let suffix = String(working[floatsStart...])
            guard let parsed = floatingLeaves(inV1Suffix: suffix) else {
                return nil
            }
            floats = parsed
            working = String(working[..<floatsStart])
            if working.count <= 5 {
                return nil
            }
        }
        let bodyStart = working.index(working.startIndex, offsetBy: 5)
        let body = String(working[bodyStart...])
        var tree: [TmuxLayoutNode] = []
        guard parseLayout(body, range: body.startIndex..<body.endIndex, into: &tree),
              let first = tree.first else {
            return nil
        }
        var root = first
        if let floats, !floats.isEmpty {
            let floatPanes = Set(floats.compactMap(\.windowPane))
            if let trimmed = removingWindowPanes(floatPanes, from: root) {
                root = trimmed
            } else {
                root = TmuxLayoutNode(type: .vSplit, children: [])
            }
        }
        if root.type == .leaf {
            let old = root
            root = TmuxLayoutNode(type: .vSplit, width: old.width, height: old.height, children: [old])
        }
        if let size = windowSize(in: working, allowLoose: floats != nil) {
            root.width = size.width
            root.height = size.height
        }
        if let floats {
            root.floatingPanes = Array(floats.reversed())
        }
        return coalesced(root)
    }

    private static func windowSize(in layout: String, allowLoose: Bool) -> (width: Int, height: Int)? {
        let strict = "^[0-9a-fA-F]{4},([0-9]+)x([0-9]+),[0-9]+,[0-9]+[\\[{]"
        if let groups = capture(layout, pattern: strict), groups.count >= 2,
           let width = Int(groups[0]), let height = Int(groups[1]) {
            return (width, height)
        }
        if allowLoose {
            let loose = "^[0-9a-fA-F]{4},([0-9]+)x([0-9]+),"
            if let groups = capture(layout, pattern: loose), groups.count >= 2,
               let width = Int(groups[0]), let height = Int(groups[1]) {
                return (width, height)
            }
        }
        return nil
    }

    private static func matches(_ string: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(string.startIndex..., in: string)
        return regex.firstMatch(in: string, range: range) != nil
            && regex.rangeOfFirstMatch(in: string, range: range).length == (string as NSString).length
    }

    private static func capture(_ string: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            let captureRange = match.range(at: index)
            guard captureRange.location != NSNotFound,
                  let swiftRange = Range(captureRange, in: string) else {
                return nil
            }
            return String(string[swiftRange])
        }
    }

    private static func floatingLeaves(inV1Suffix suffix: String) -> [TmuxLayoutNode]? {
        guard suffix.hasSuffix(">"), suffix.count >= 3 else {
            return nil
        }
        let body = String(suffix.dropFirst().dropLast())
        let cell = "([0-9]+)x([0-9]+),(-?[0-9]+),(-?[0-9]+),([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: cell) else {
            return nil
        }
        let nsBody = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: nsBody.length))
        if matches.isEmpty {
            return nil
        }
        var result: [TmuxLayoutNode] = []
        for match in matches {
            guard match.numberOfRanges >= 6,
                  let width = Int(nsBody.substring(with: match.range(at: 1))),
                  let height = Int(nsBody.substring(with: match.range(at: 2))),
                  let x = Int(nsBody.substring(with: match.range(at: 3))),
                  let y = Int(nsBody.substring(with: match.range(at: 4))),
                  let pane = Int(nsBody.substring(with: match.range(at: 5))) else {
                return nil
            }
            result.append(TmuxLayoutNode(
                type: .leaf,
                width: width,
                height: height,
                x: x,
                y: y,
                windowPane: pane,
                zIndex: result.count
            ))
        }
        return result
    }

    private static func removingWindowPanes(_ panes: Set<Int>, from node: TmuxLayoutNode) -> TmuxLayoutNode? {
        if node.type == .leaf {
            if let pane = node.windowPane, panes.contains(pane) {
                return nil
            }
            return node
        }
        let kept = node.children.compactMap { removingWindowPanes(panes, from: $0) }
        if kept.isEmpty {
            return nil
        }
        if kept.count == 1 {
            return kept[0]
        }
        node.children = kept
        return node
    }

    private static func coalesced(_ node: TmuxLayoutNode) -> TmuxLayoutNode {
        if node.type == .vSplit || node.type == .hSplit {
            var coalescedChildren: [TmuxLayoutNode] = []
            for child in node.children {
                let coalescedChild = coalesced(child)
                if coalescedChild.type == node.type {
                    coalescedChildren.append(contentsOf: coalescedChild.children)
                } else {
                    coalescedChildren.append(coalescedChild)
                }
            }
            node.children = coalescedChildren
        }
        return node
    }

    private static func nodeType(in layout: String, range: Range<String.Index>) -> TmuxLayoutNodeType {
        let slice = layout[range]
        let square = slice.firstIndex(of: "[")
        let curly = slice.firstIndex(of: "{")
        switch (square, curly) {
        case (nil, nil):
            return .leaf
        case (let s?, let c?):
            return s < c ? .hSplit : .vSplit
        case (_?, nil):
            return .hSplit
        case (nil, _?):
            return .vSplit
        }
    }

    private static func dictForLeaf(in layout: String, range: Range<String.Index>) -> TmuxLayoutNode? {
        let slice = String(layout[range])
        guard let groups = capture(slice, pattern: "([0-9]+)x([0-9]+),(-?[0-9]+),(-?[0-9]+),?([0-9]+)?"),
              groups.count >= 4,
              let width = Int(groups[0]),
              let height = Int(groups[1]),
              let x = Int(groups[2]),
              let y = Int(groups[3]) else {
            return nil
        }
        let pane = groups.count > 4 ? Int(groups[4]) : nil
        return TmuxLayoutNode(type: .leaf, width: width, height: height, x: x, y: y, windowPane: pane)
    }

    private static func rangeOfChildren(in layout: String,
                                        range: Range<String.Index>,
                                        open: Character,
                                        close: Character) -> Range<String.Index>? {
        guard let openIndex = layout[range].firstIndex(of: open) else {
            return nil
        }
        var count = 0
        var i = openIndex
        while i < range.upperBound {
            let c = layout[i]
            if c == "[" || c == "{" {
                count += 1
            } else if c == "]" || c == "}" {
                count -= 1
                if count == 0 {
                    let start = layout.index(after: openIndex)
                    return start..<i
                }
            }
            i = layout.index(after: i)
        }
        return nil
    }

    private static func splitOffFirstLayout(_ layouts: String) -> (first: String, rest: String)? {
        if layouts.isEmpty {
            return nil
        }
        let pattern = "^(,?)([0-9]+x[0-9]+,-?[0-9]+,-?[0-9]+(?:,[0-9]+)?)(.*)"
        guard let groups = capture(layouts, pattern: pattern), groups.count >= 3 else {
            return nil
        }
        let head = groups[1]
        let suffix = groups[2]
        if suffix.isEmpty {
            return (head, "")
        }
        let first = suffix[suffix.startIndex]
        if first == "," {
            return (head, String(suffix.dropFirst()))
        }
        if first == "[" || first == "{" {
            let close: Character = first == "[" ? "]" : "}"
            guard let children = rangeOfChildren(in: suffix,
                                                 range: suffix.startIndex..<suffix.endIndex,
                                                 open: first,
                                                 close: close) else {
                return nil
            }
            let afterClose = suffix.index(after: children.upperBound)
            let wrapped = head + String(suffix[suffix.startIndex..<afterClose])
            return (wrapped, String(suffix[afterClose...]))
        }
        return nil
    }

    private static func parseLayoutArray(_ layout: String,
                                         range: Range<String.Index>,
                                         into tree: inout [TmuxLayoutNode]) -> Bool {
        var rest = String(layout[range])
        while let split = splitOffFirstLayout(rest) {
            var nested: [TmuxLayoutNode] = []
            guard parseLayout(split.first,
                              range: split.first.startIndex..<split.first.endIndex,
                              into: &nested) else {
                return false
            }
            tree.append(contentsOf: nested)
            rest = split.rest
            if rest.hasPrefix(",") {
                rest = String(rest.dropFirst())
            }
        }
        return true
    }

    private static func parseLayout(_ layout: String,
                                    range: Range<String.Index>,
                                    into tree: inout [TmuxLayoutNode]) -> Bool {
        let type = nodeType(in: layout, range: range)
        switch type {
        case .leaf:
            guard let leaf = dictForLeaf(in: layout, range: range) else {
                return false
            }
            tree.append(leaf)
            return true
        case .hSplit, .vSplit:
            let open: Character = type == .hSplit ? "[" : "{"
            let close: Character = type == .hSplit ? "]" : "}"
            guard let childrenRange = rangeOfChildren(in: layout, range: range, open: open, close: close) else {
                return false
            }
            var children: [TmuxLayoutNode] = []
            guard parseLayoutArray(layout, range: childrenRange, into: &children) else {
                return false
            }
            tree.append(TmuxLayoutNode(type: type, children: children))
            return true
        }
    }
}
