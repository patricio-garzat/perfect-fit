// Where each piece is, and everything derived from it.

public struct Placement: Hashable, Codable, Sendable {
    public var origin: Cell        // top-left cell of the rotated footprint
    public var rotation: Rotation
    public init(origin: Cell, rotation: Rotation) { self.origin = origin; self.rotation = rotation }
}

public extension FurnitureKind {
    func rotatedSize(_ r: Rotation) -> (w: Int, h: Int) { r.size(w: w, d: d) }

    func cell(u: Int, v: Int, at p: Placement) -> Cell { p.origin + p.rotation.map(u: u, v: v, w: w, d: d) }

    func cells(at p: Placement) -> [Cell] {
        var r: [Cell] = []; r.reserveCapacity(w * d)
        for v in 0..<d { for u in 0..<w { r.append(cell(u: u, v: v, at: p)) } }
        return r
    }
    func cells(of rect: LocalRect, at p: Placement) -> [Cell] { rect.cells.map { cell(u: $0.0, v: $0.1, at: p) } }
    /// Cells right behind the piece (where the wall must be).
    func backCells(at p: Placement) -> [Cell] { (0..<w).map { cell(u: $0, v: -1, at: p) } }
    /// Cells at the head of a bed (back row).
    func headCells(at p: Placement) -> [Cell] { (0..<w).map { cell(u: $0, v: 0, at: p) } }
    /// Area right in front of a seat (two rows deep), for coffee tables and rugs.
    func frontArea(at p: Placement) -> [Cell] { cells(of: LocalRect(u: 0, v: d, w: w, h: 2), at: p) }
}

/// One evaluation of a layout against the level's rules.
public enum Issue: Hashable, Sendable {
    case notPlaced(Int)            // pieces still in the tray
    case outsideRoom(Int)
    case overlaps(Int)
    case needsWall(Int)            // back not against a wall
    case blocksDoor(Int)           // inside the door swing
    case zoneBlocked(Int)          // no room to use it
    case unreachable(Int)          // its use zone can't be reached from the door
    case blocksWindow(Int)         // tall piece in front of a window
    case needsWindow(Int)          // desk not by a window

    public var piece: Int? {
        switch self {
        case .notPlaced: return nil
        case .outsideRoom(let i), .overlaps(let i), .needsWall(let i), .blocksDoor(let i), .zoneBlocked(let i),
             .unreachable(let i), .blocksWindow(let i), .needsWindow(let i): return i
        }
    }
}

public struct Evaluation: Sendable {
    public var issues: [Issue] = []
    public var valid: Bool { issues.isEmpty }
    public var harmonyMet = 0, harmonyTotal = 0
    public var harmony: Bool { harmonyMet == harmonyTotal }
    /// Every free spot of floor can be reached from the door.
    public var flow = false
    /// Per piece: which preference is met (nil = this piece has none that applies).
    public var preferenceMet: [Int: Bool] = [:]
    public var stars: Int { valid ? 1 + (harmony ? 1 : 0) + (flow ? 1 : 0) : 0 }
    /// Cells of use zones that are blocked, per piece (to draw them).
    public var blockedZoneCells: [Int: [Cell]] = [:]
    public var reachable: Set<Cell> = []
}

public struct Layout: Sendable {
    public let level: Level
    public let room: Room
    public let kinds: [FurnitureKind]
    public var placements: [Placement?]

    public init(level: Level) {
        self.level = level
        room = Room(level)
        kinds = level.pieceKinds.map(Catalog.kind)
        placements = Array(repeating: nil, count: kinds.count)
    }

    public var placedCount: Int { placements.compactMap { $0 }.count }

    /// Solid cells → piece index (columns are -1).
    public func solidMap(excluding skip: Int? = nil) -> [Cell: Int] {
        var m: [Cell: Int] = [:]
        for c in room.columns { m[c] = -1 }
        for (i, p) in placements.enumerated() where i != skip {
            guard let p, kinds[i].layer == .solid else { continue }
            for c in kinds[i].cells(at: p) { m[c] = i }
        }
        return m
    }

    /// Hard limits: a piece can only be dropped inside the room and on free floor.
    public func canPlace(_ i: Int, at p: Placement) -> Bool {
        let k = kinds[i]
        let cells = k.cells(at: p)
        guard cells.allSatisfy(room.isFloor) else { return false }
        if k.layer == .floor {
            for (j, q) in placements.enumerated() where j != i {
                guard let q, kinds[j].layer == .floor else { continue }
                if !Set(kinds[j].cells(at: q)).isDisjoint(with: cells) { return false }
            }
            return true
        }
        let solid = solidMap(excluding: i)
        return cells.allSatisfy { solid[$0] == nil }
    }

    public func evaluate() -> Evaluation {
        var e = Evaluation()
        let missing = placements.filter { $0 == nil }.count
        if missing > 0 { e.issues.append(.notPlaced(missing)) }
        let solid = solidMap()
        let clearance = level.has(.clearance), access = level.has(.access), windows = level.has(.windows)

        // free floor and what the door reaches
        var free = Set<Cell>()
        for c in room.floor where solid[c] == nil { free.insert(c) }
        var reach = Set<Cell>(), queue = room.doorCells.filter { free.contains($0) }
        reach.formUnion(queue)
        while let c = queue.popLast() { for n in c.neighbors where free.contains(n) && !reach.contains(n) { reach.insert(n); queue.append(n) } }
        e.reachable = reach
        e.flow = missing == 0 && !room.doorCells.isEmpty && reach.count == free.count

        for (i, p) in placements.enumerated() {
            guard let p else { continue }
            let k = kinds[i]
            let cells = k.cells(at: p)
            if !cells.allSatisfy(room.isFloor) { e.issues.append(.outsideRoom(i)); continue }
            if k.layer == .solid {
                if cells.contains(where: { solid[$0] != i }) { e.issues.append(.overlaps(i)) }
                if cells.contains(where: room.doorSwing.contains) { e.issues.append(.blocksDoor(i)) }
            }
            if k.wallBack && !k.backCells(at: p).allSatisfy({ room.isWall($0) || room.columns.contains($0) }) { e.issues.append(.needsWall(i)) }
            if windows {
                if k.tall && cells.contains(where: room.windowCells.contains) { e.issues.append(.blocksWindow(i)) }
                if k.needsWindow && !room.windows.isEmpty && !cells.contains(where: room.windowCells.contains) { e.issues.append(.needsWindow(i)) }
            }
            if clearance && !k.zones.isEmpty {
                var okZones: [[Cell]] = [], blocked: [Cell] = []
                for z in k.zones {
                    let zc = k.cells(of: z.rect, at: p)
                    let bad = zc.filter { c in
                        if !room.isFloor(c) || room.columns.contains(c) { return true }
                        if let o = solid[c], o >= 0 { return !z.allows.contains(kinds[o].id) }
                        return false
                    }
                    if bad.isEmpty { okZones.append(zc) } else { blocked += bad.filter(room.isFloor) }
                }
                let satisfied = k.anyZone ? !okZones.isEmpty : okZones.count == k.zones.count
                if !satisfied { e.issues.append(.zoneBlocked(i)); e.blockedZoneCells[i] = blocked }
                else if access && missing == 0 && !okZones.contains(where: { $0.contains(where: reach.contains) }) { e.issues.append(.unreachable(i)) }
            }
        }

        // harmony
        let placedKinds = Set(zip(kinds, placements).compactMap { $1 == nil ? nil : $0.id })
        for (i, p) in placements.enumerated() {
            guard let p, let pref = kinds[i].preference, let met = preference(pref, i, p, placedKinds, solid) else { continue }
            e.preferenceMet[i] = met
            e.harmonyTotal += 1; if met { e.harmonyMet += 1 }
        }
        return e
    }

    /// nil = doesn't apply in this room.
    func preference(_ pref: Preference, _ i: Int, _ p: Placement, _ present: Set<String>, _ solid: [Cell: Int]) -> Bool? {
        let k = kinds[i]
        let cells = k.cells(at: p)
        func others(_ test: (FurnitureKind) -> Bool) -> [(FurnitureKind, Placement)] {
            zip(kinds, placements).enumerated().compactMap { j, kp in j != i && kp.1 != nil && test(kp.0) ? (kp.0, kp.1!) : nil }
        }
        switch pref {
        case .nextToBedHead:
            let beds = others { $0.isBed }
            if beds.isEmpty { return present.contains(where: { $0.hasPrefix("bed") }) ? false : nil }
            return beds.contains { b, bp in [b.cell(u: -1, v: 0, at: bp), b.cell(u: b.w, v: 0, at: bp)].contains(cells[0]) }
        case .bothSidesFree:
            return k.zones.allSatisfy { z in
                k.cells(of: z.rect, at: p).allSatisfy { room.isFloor($0) && !room.columns.contains($0) && solid[$0] == nil }
            }
        case .atDesk:
            let tables = others { $0.id == "desk" || $0.id == "round_table" }
            if tables.isEmpty { return nil }
            let f = k.cell(u: 0, v: 1, at: p)
            return tables.contains { t, tp in t.cells(at: tp).contains(f) }
        case .inFrontOfSeat:
            let seats = others { $0.isSeat }
            if seats.isEmpty { return nil }
            return seats.contains { s, sp in !Set(s.frontArea(at: sp)).isDisjoint(with: cells) }
        case .nextToSeat:
            let near = others { $0.isSeat || $0.isBed || $0.id == "desk" }
            if near.isEmpty { return nil }
            let around = Set(cells.flatMap(\.neighbors))
            return near.contains { s, sp in !Set(s.cells(at: sp)).isDisjoint(with: around) }
        case .lightOrCorner:
            return room.windows.isEmpty ? room.isCorner(cells[0]) : cells.contains(where: room.windowCells.contains)
        case .underBedOrSeat:
            let hosts = others { $0.isBed || $0.isSeat }
            if hosts.isEmpty { return nil }
            return hosts.contains { h, hp in
                let area = h.cells(at: hp) + (h.isSeat ? h.frontArea(at: hp) : [])
                return !Set(area).isDisjoint(with: cells)
            }
        case .nearWindow:
            if room.windows.isEmpty { return nil }
            return cells.contains(where: room.windowCells.contains)
        }
    }
}
