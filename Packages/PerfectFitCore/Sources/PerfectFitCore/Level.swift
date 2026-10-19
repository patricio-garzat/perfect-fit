import Foundation

// A level, as stored in Resources/Levels/NN.json.
//
// {
//   "id": 1,
//   "name": { "en": "First Light", "es": "Primera luz" },
//   "style": "oak",                         // look of floor/walls/fabrics (see RoomStyle in the app)
//   "shape": ["######", "######", ...],     // '#' floor, '.' outside the room, 'X' fixed column
//   "doors":   [{ "cell": [0, 5], "side": "W", "width": 2 }],
//   "windows": [{ "cell": [2, 0], "side": "N", "width": 2 }],
//   "pieces":  ["bed_single", "nightstand", { "kind": "chair", "count": 2 }],
//   "rules":   ["clearance", "access", "windows"],
//   "hint": { "en": "...", "es": "..." }    // optional line shown when the level starts
// }

public struct Localized: Codable, Hashable, Sendable {
    public var en: String
    public var es: String
    public init(en: String, es: String) { self.en = en; self.es = es }
    public func text(_ lang: String) -> String { lang == "es" ? es : en }
}

public struct Opening: Codable, Hashable, Sendable {
    public var cell: Cell
    public var side: Side
    public var width: Int

    enum CodingKeys: String, CodingKey { case cell, side, width }
    public init(cell: Cell, side: Side, width: Int) { self.cell = cell; self.side = side; self.width = width }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let xy = try c.decode([Int].self, forKey: .cell)
        cell = Cell(xy[0], xy[1]); side = try c.decode(Side.self, forKey: .side)
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 2
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode([cell.x, cell.y], forKey: .cell); try c.encode(side, forKey: .side); try c.encode(width, forKey: .width)
    }
    /// Room cells along the wall.
    public var cells: [Cell] { (0..<width).map { i in Cell(cell.x + side.along.x * i, cell.y + side.along.y * i) } }
}

public enum Rule: String, Codable, Sendable, CaseIterable {
    case clearance  // use zones must be free (bed side, wardrobe doors, chair pull-out…)
    case access     // every use zone reachable from the door
    case windows    // tall pieces keep windows clear; desks go by a window
}

public struct PieceSpec: Codable, Hashable, Sendable {
    public var kind: String
    public var count: Int
    public init(from d: Decoder) throws {
        if let s = try? d.singleValueContainer().decode(String.self) { kind = s; count = 1; return }
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind); count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
    }
    public init(kind: String, count: Int = 1) { self.kind = kind; self.count = count }
}

public struct Level: Codable, Sendable, Identifiable {
    public var id: Int
    public var name: Localized
    public var style: String
    public var shape: [String]
    public var doors: [Opening]
    public var windows: [Opening]
    public var pieces: [PieceSpec]
    public var rules: [Rule]
    public var hint: Localized?

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(Localized.self, forKey: .name)
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? "oak"
        shape = try c.decode([String].self, forKey: .shape)
        doors = try c.decodeIfPresent([Opening].self, forKey: .doors) ?? []
        windows = try c.decodeIfPresent([Opening].self, forKey: .windows) ?? []
        pieces = try c.decode([PieceSpec].self, forKey: .pieces)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        hint = try c.decodeIfPresent(Localized.self, forKey: .hint)
    }

    public static func load(_ url: URL) throws -> Level { try JSONDecoder().decode(Level.self, from: Data(contentsOf: url)) }

    /// Every piece instance, in a stable order (index = piece id inside the level).
    public var pieceKinds: [String] { pieces.flatMap { Array(repeating: $0.kind, count: $0.count) } }
    public func has(_ r: Rule) -> Bool { rules.contains(r) }
}

/// The room as the rules see it.
public struct Room: Sendable {
    public let width: Int, height: Int
    public let floor: Set<Cell>          // walkable cells
    public let columns: Set<Cell>        // fixed obstacles (structural columns)
    public let doorSwing: Set<Cell>      // cells a door sweeps; must stay clear
    public let doorCells: [Cell]         // room cells right inside each door (start of every path)
    public let windowCells: Set<Cell>    // room cells along a window
    public let doors: [Opening]
    public let windows: [Opening]

    public init(_ level: Level) {
        height = level.shape.count
        width = level.shape.map(\.count).max() ?? 0
        var f = Set<Cell>(), cols = Set<Cell>()
        for (y, row) in level.shape.enumerated() {
            for (x, ch) in row.enumerated() {
                if ch == "#" { f.insert(Cell(x, y)) }
                if ch == "X" { f.insert(Cell(x, y)); cols.insert(Cell(x, y)) }
            }
        }
        floor = f; columns = cols; doors = level.doors; windows = level.windows
        var swing = Set<Cell>(), inside: [Cell] = []
        for d in level.doors {
            inside += d.cells
            // the leaf is as wide as the door and swings into the room as deep as it is wide
            for c in d.cells { for k in 0..<d.width { swing.insert(Cell(c.x - d.side.outward.x * k, c.y - d.side.outward.y * k)) } }
        }
        doorSwing = swing.intersection(f); doorCells = inside
        windowCells = Set(level.windows.flatMap(\.cells))
    }

    public func isFloor(_ c: Cell) -> Bool { floor.contains(c) }
    /// A wall (or the outside) is right behind this cell edge.
    public func isWall(_ c: Cell) -> Bool { !floor.contains(c) }
    public func isCorner(_ c: Cell) -> Bool {
        let n = isWall(Cell(c.x, c.y - 1)), s = isWall(Cell(c.x, c.y + 1)), e = isWall(Cell(c.x + 1, c.y)), w = isWall(Cell(c.x - 1, c.y))
        return (n || s) && (e || w)
    }
}

public extension Level {
    /// Problems in the level file itself (openings off the wall, unknown pieces…). Empty = fine.
    func dataProblems() -> [String] {
        var out: [String] = []
        let room = Room(self)
        for (what, list) in [("door", doors), ("window", windows)] {
            for o in list {
                for c in o.cells where !room.floor.contains(c) || room.floor.contains(c + o.side.outward) {
                    out.append("\(what) at \(o.cell) \(o.side.rawValue): cell \(c) is not on that wall")
                }
            }
        }
        for k in pieceKinds where Catalog.kinds[k] == nil { out.append("unknown piece \(k)") }
        if doors.isEmpty { out.append("no door") }
        return out
    }
}
