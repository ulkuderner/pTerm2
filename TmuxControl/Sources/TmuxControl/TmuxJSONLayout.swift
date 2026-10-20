import Foundation

/// Parses the JSON (v2) window layouts that tmux sends a control client that
/// opted in with `refresh-client -f new-layouts`.
public enum TmuxJSONLayoutParser {
    public static func isJSONLayout(_ layout: String) -> Bool {
        return layout.hasPrefix("{")
    }

    public static func parsedLayout(from layout: String) -> TmuxLayoutNode? {
        do {
            return try parse(layout)
        } catch {
            return nil
        }
    }

    private struct Malformed: Error {
        let reason: String
    }

    private static func parse(_ layout: String) throws -> TmuxLayoutNode {
        guard let data = layout.data(using: .utf8),
              let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Malformed(reason: "not an object")
        }
        guard let version = integer(top["V"]), version == 2 else {
            throw Malformed(reason: "unsupported version")
        }
        guard let rootCell = top["L"] as? [String: Any] else {
            throw Malformed(reason: "no root cell")
        }
        var floats: [(z: Int, leaf: TmuxLayoutNode)] = []
        let tiled = try node(for: rootCell, floats: &floats)

        let root: TmuxLayoutNode
        if let tiled, tiled.type != .leaf {
            root = tiled
        } else {
            root = TmuxLayoutNode(type: .vSplit, children: tiled.map { [$0] } ?? [])
        }
        let rootIsFloating = rootCell["z"] != nil
        if !rootIsFloating {
            root.width = try dimension(rootCell, "w")
            root.height = try dimension(rootCell, "h")
        }
        root.floatingPanes = floats.sorted { $0.z > $1.z }.map(\.leaf)
        return root
    }

    private static func node(for cell: [String: Any],
                             floats: inout [(z: Int, leaf: TmuxLayoutNode)]) throws -> TmuxLayoutNode? {
        guard let type = cell["t"] as? String else {
            throw Malformed(reason: "cell has no type")
        }
        switch type {
        case "p":
            let leaf = try self.leaf(for: cell)
            if cell["z"] != nil {
                guard let z = integer(cell["z"]), z >= 0 else {
                    throw Malformed(reason: "bad z-index")
                }
                leaf.zIndex = z
                floats.append((z: z, leaf: leaf))
                return nil
            }
            return leaf
        case "h", "v":
            guard let cells = cell["c"] as? [[String: Any]], !cells.isEmpty else {
                throw Malformed(reason: "node has no children")
            }
            let children = try cells.compactMap { try node(for: $0, floats: &floats) }
            switch children.count {
            case 0:
                return nil
            case 1:
                return children[0]
            default:
                let nodeType: TmuxLayoutNodeType = (type == "h") ? .vSplit : .hSplit
                return TmuxLayoutNode(type: nodeType, children: children)
            }
        default:
            throw Malformed(reason: "unknown cell type \(type)")
        }
    }

    private static func leaf(for cell: [String: Any]) throws -> TmuxLayoutNode {
        guard let paneID = cell["I"] as? String,
              paneID.hasPrefix("%"),
              let windowPane = Int(paneID.dropFirst()) else {
            throw Malformed(reason: "pane has no ID")
        }
        return TmuxLayoutNode(
            type: .leaf,
            width: try dimension(cell, "w"),
            height: try dimension(cell, "h"),
            x: try offset(cell, "x"),
            y: try offset(cell, "y"),
            windowPane: windowPane
        )
    }

    private static func dimension(_ cell: [String: Any], _ key: String) throws -> Int {
        guard let value = integer(cell[key]), value >= 0 else {
            throw Malformed(reason: "bad \(key)")
        }
        return value
    }

    private static func offset(_ cell: [String: Any], _ key: String) throws -> Int {
        guard let value = integer(cell[key]) else {
            throw Malformed(reason: "bad \(key)")
        }
        return value
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded() else {
            return nil
        }
        return number.intValue
    }
}
