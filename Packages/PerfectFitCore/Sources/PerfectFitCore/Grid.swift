// Logical grid. One cell = 50 cm. x grows to the right (+X in 3D), y grows "down" the plan (+Z in 3D).
public let cellSize: Double = 0.5

public struct Cell: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
    public var description: String { "(\(x),\(y))" }
    public static func + (a: Cell, b: Cell) -> Cell { Cell(a.x + b.x, a.y + b.y) }
    public var neighbors: [Cell] { [Cell(x + 1, y), Cell(x - 1, y), Cell(x, y + 1), Cell(x, y - 1)] }
}

/// Wall side of a cell, as seen on the plan.
public enum Side: String, Codable, Sendable, CaseIterable {
    case north = "N", east = "E", south = "S", west = "W"
    /// Step from a room cell through this wall.
    public var outward: Cell {
        switch self {
        case .north: return Cell(0, -1)
        case .south: return Cell(0, 1)
        case .east: return Cell(1, 0)
        case .west: return Cell(-1, 0)
        }
    }
    /// Step along the wall (to the next cell of a door or window).
    public var along: Cell { (self == .north || self == .south) ? Cell(1, 0) : Cell(0, 1) }
}

/// Quarter turns, clockwise seen from above. 0 = front faces +y (toward the camera's default side).
/// In SceneKit the node gets eulerAngles.y = turns · 90°, which turns the model's +Z front to +X at 1 turn.
public struct Rotation: Hashable, Codable, Sendable {
    public var turns: Int
    public init(_ t: Int) { turns = ((t % 4) + 4) % 4 }
    public var next: Rotation { Rotation(turns + 1) }
    public static let all = (0..<4).map(Rotation.init)

    /// Size of the rotated bounding box.
    public func size(w: Int, d: Int) -> (w: Int, h: Int) { turns % 2 == 0 ? (w, d) : (d, w) }

    /// Local cell (u across the width, v from back (0) to front (d-1)) → grid offset inside the rotated box.
    /// Works for u/v outside the footprint too (zones in front, behind or at the sides).
    public func map(u: Int, v: Int, w: Int, d: Int) -> Cell {
        switch turns {
        case 0: return Cell(u, v)                  // front → +y
        case 1: return Cell(v, w - 1 - u)          // front → +x
        case 2: return Cell(w - 1 - u, d - 1 - v)  // front → −y
        default: return Cell(d - 1 - v, u)         // front → −x
        }
    }

    /// Direction the front faces on the plan.
    public var front: Cell {
        switch turns { case 0: return Cell(0, 1); case 1: return Cell(1, 0); case 2: return Cell(0, -1); default: return Cell(-1, 0) }
    }
}

/// A rectangle in a piece's local coordinates (u, v), possibly outside the footprint.
public struct LocalRect: Hashable, Codable, Sendable {
    public var u: Int, v: Int, w: Int, h: Int
    public init(u: Int, v: Int, w: Int, h: Int) { self.u = u; self.v = v; self.w = w; self.h = h }
    public var cells: [(Int, Int)] { var r: [(Int, Int)] = []; for j in v..<(v + h) { for i in u..<(u + w) { r.append((i, j)) } }; return r }
}
