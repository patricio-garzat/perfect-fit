import Foundation

/// Exhaustive search over every placement of every piece. Used by the level tests (each level must have a
/// solution, and a 3-star one), by the level tool, and by in-game hints.
/// Pruning only removes layouts the rules would reject anyway; every complete layout is checked by `Layout.evaluate()`.
public struct Solver {
    public struct Result: Sendable {
        public var solutions = 0
        public var byStars = [0, 0, 0, 0]
        public var best: [Placement]? = nil
        public var bestStars = 0
        public var first: [Placement]? = nil
        public var complete = true   // false if a limit stopped the search
        public var nodes = 0
        public var withHarmony = 0, withFlow = 0
    }

    struct Candidate {
        let placement: Placement
        let cells: [Int]
        let zones: [[Int]]        // use zones (cell indices), only with the clearance rule
        let allows: [UInt64]      // kinds allowed inside each zone
        let reserve: Bool         // all zones must stay clear (false for a bed: one free side is enough)
    }

    let level: Level
    let room: Room
    let kinds: [FurnitureKind]
    let W: Int, H: Int
    var order: [Int] = []
    var candidates: [[Candidate]] = []
    let kindBit: [UInt64]

    public init(level: Level) {
        self.level = level
        room = Room(level)
        kinds = level.pieceKinds.map(Catalog.kind)
        W = room.width; H = room.height
        let ids = Array(Set(kinds.map(\.id))).sorted()
        kindBit = kinds.map { 1 << UInt64(ids.firstIndex(of: $0.id)!) }
        let bitOf = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, UInt64(1) << UInt64($0)) })

        let layout = Layout(level: level)
        let clearance = level.has(.clearance), windows = level.has(.windows)
        var perKind: [String: [Candidate]] = [:]
        for k in Set(kinds.map(\.id)).map(Catalog.kind) {
            var list: [Candidate] = []
            var seen = Set<[Int]>()
            for r in Rotation.all {
                let (rw, rh) = k.rotatedSize(r)
                for oy in 0...(max(0, H - rh)) { for ox in 0...(max(0, W - rw)) {
                    let p = Placement(origin: Cell(ox, oy), rotation: r)
                    let cells = k.cells(at: p)
                    guard cells.allSatisfy(room.isFloor) else { continue }
                    if k.layer == .solid {
                        if cells.contains(where: { room.columns.contains($0) || room.doorSwing.contains($0) }) { continue }
                    }
                    if k.wallBack && !k.backCells(at: p).allSatisfy({ room.isWall($0) || room.columns.contains($0) }) { continue }
                    if windows {
                        if k.tall && cells.contains(where: room.windowCells.contains) { continue }
                        if k.needsWindow && !room.windows.isEmpty && !cells.contains(where: room.windowCells.contains) { continue }
                    }
                    var zones: [[Int]] = [], allows: [UInt64] = []
                    if clearance && !k.zones.isEmpty {
                        let inRoom = k.zones.map { z in k.cells(of: z.rect, at: p).allSatisfy { room.isFloor($0) && !room.columns.contains($0) } }
                        if k.anyZone ? !inRoom.contains(true) : inRoom.contains(false) { continue }
                        for (z, ok) in zip(k.zones, inRoom) where ok {
                            zones.append(k.cells(of: z.rect, at: p).map { $0.y * room.width + $0.x })
                            allows.append(z.allows.reduce(0) { $0 | (bitOf[$1] ?? 0) })
                        }
                    }
                    let idx = cells.map { $0.y * room.width + $0.x }
                    // a symmetric piece looks the same after a half turn: keep one (unless zones differ)
                    let key = idx.sorted() + (k.zones.isEmpty ? [] : [r.turns])
                    if seen.contains(key) { continue }
                    seen.insert(key)
                    list.append(Candidate(placement: p, cells: idx, zones: zones, allows: allows, reserve: !k.anyZone))
                }}
            }
            perKind[k.id] = list
        }
        _ = layout
        candidates = kinds.map { perKind[$0.id]! }
        // big solid pieces first, rugs last; identical pieces next to each other
        order = Array(kinds.indices).sorted { a, b in
            let ka = kinds[a], kb = kinds[b]
            if ka.layer != kb.layer { return ka.layer == .solid }
            if ka.w * ka.d != kb.w * kb.d { return ka.w * ka.d > kb.w * kb.d }
            if ka.id != kb.id { return ka.id < kb.id }
            return a < b
        }
    }

    /// - Parameters:
    ///   - fixed: pieces that must stay where they are (for hints).
    ///   - stopAtFirst: return as soon as a valid layout with at least `wantStars` is found.
    ///   - wantStars: with 2 or more, candidates that miss their harmony preference are skipped.
    ///   - seed: shuffles the candidate order (random restarts find rare layouts much faster).
    public func solve(fixed: [Int: Placement] = [:], stopAtFirst: Bool = false, wantStars: Int = 1,
                      seed: UInt64? = nil, maxNodes: Int = .max, deadline: Date? = nil) -> Result {
        var res = Result()
        let n = kinds.count
        var solid = [Int](repeating: -1, count: W * H)
        var rug = [Bool](repeating: false, count: W * H)
        var reserved = [[UInt64]](repeating: [], count: W * H)   // allow-masks of zones covering each cell
        var chosen = [Int](repeating: -1, count: n)
        var layout = Layout(level: level)
        var stop = false
        let access = level.has(.access)
        let harmonyOnly = wantStars >= 2
        let floorIdx = Set(room.floor.subtracting(room.columns).map { $0.y * W + $0.x })
        let doorIdx = room.doorCells.map { $0.y * W + $0.x }
        var lists = candidates
        if let seed {
            var rng = SplitMix(seed)
            for i in lists.indices { lists[i].shuffle(using: &rng) }
        }

        func fits(_ i: Int, _ c: Candidate) -> Bool {
            if kinds[i].layer == .floor { return !c.cells.contains { rug[$0] } }
            let bit = kindBit[i]
            for x in c.cells {
                if solid[x] >= 0 { return false }
                for m in reserved[x] where m & bit == 0 { return false }
            }
            if c.reserve {
                for (z, zone) in c.zones.enumerated() {
                    for x in zone { let o = solid[x]; if o >= 0 && c.allows[z] & kindBit[o] == 0 { return false } }
                }
            }
            return true
        }
        func apply(_ i: Int, _ c: Candidate, _ on: Bool) {
            layout.placements[i] = on ? c.placement : nil
            if kinds[i].layer == .floor { for x in c.cells { rug[x] = on }; return }
            for x in c.cells { solid[x] = on ? i : -1 }
            if c.reserve {
                for (z, zone) in c.zones.enumerated() {
                    for x in zone { if on { reserved[x].append(c.allows[z]) } else { reserved[x].removeLast() } }
                }
            }
        }
        /// Reach from the door only shrinks as pieces are added, so a piece that can't be used now never will.
        func stillUsable(_ depth: Int) -> Bool {
            var reach = [Bool](repeating: false, count: W * H)
            var queue = doorIdx.filter { solid[$0] < 0 }
            for q in queue { reach[q] = true }
            while let c = queue.popLast() {
                let x = c % W, y = c / W
                for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < W && ny < H {
                    let k = ny * W + nx
                    if !reach[k] && solid[k] < 0 && floorIdx.contains(k) { reach[k] = true; queue.append(k) }
                }
            }
            for d in 0...depth {
                let i = order[d]
                guard chosen[i] >= 0 else { continue }
                let c = lists[i][chosen[i]]
                if c.zones.isEmpty { continue }
                var ok = false
                for (z, zone) in c.zones.enumerated() {
                    let clear = zone.allSatisfy { x in let o = solid[x]; return o < 0 || c.allows[z] & kindBit[o] != 0 }
                    if clear && zone.contains(where: { reach[$0] }) { ok = true; break }
                }
                if !ok { return false }
            }
            return true
        }

        let solidOrder = order.filter { kinds[$0].layer == .solid }
        /// For 3 stars no floor may be cut off from the door. Cut-off floor can never reconnect, so the pieces
        /// still to place must be able to cover it.
        func pocketsFillable(_ depth: Int) -> Bool {
            var remainingArea = 0, remainingCount = 0
            for i in solidOrder where chosen[i] < 0 { remainingArea += kinds[i].w * kinds[i].d; remainingCount += 1 }
            var seen = [Bool](repeating: false, count: W * H)
            var queue = doorIdx.filter { solid[$0] < 0 }
            for q in queue { seen[q] = true }
            func flood() -> Int {
                var size = 0
                while let c = queue.popLast() {
                    size += 1
                    let x = c % W, y = c / W
                    for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] where nx >= 0 && ny >= 0 && nx < W && ny < H {
                        let k = ny * W + nx
                        if !seen[k] && solid[k] < 0 && floorIdx.contains(k) { seen[k] = true; queue.append(k) }
                    }
                }
                return size
            }
            _ = flood()
            var pocketArea = 0, pockets = 0
            for k in floorIdx where !seen[k] && solid[k] < 0 {
                seen[k] = true; queue = [k]; pocketArea += flood(); pockets += 1
                if pocketArea > remainingArea || pockets > remainingCount { return false }
            }
            return true
        }

        func dfs(_ depth: Int) {
            if stop { return }
            res.nodes += 1
            if res.nodes > maxNodes || (res.nodes & 1023 == 0 && deadline.map { Date() > $0 } == true) { res.complete = false; stop = true; return }
            if depth == n {
                let e = layout.evaluate()
                guard e.valid else { return }
                res.solutions += 1
                res.byStars[e.stars] += 1
                if e.harmony { res.withHarmony += 1 }
                if e.flow { res.withFlow += 1 }
                let sol = layout.placements.map { $0! }
                if res.first == nil { res.first = sol }
                if e.stars > res.bestStars { res.bestStars = e.stars; res.best = sol }
                if stopAtFirst && e.stars >= wantStars { stop = true }
                return
            }
            let i = order[depth]
            func attempt(_ ci: Int, _ c: Candidate) {
                guard fits(i, c) else { return }
                chosen[i] = ci; apply(i, c, true)
                var ok = true
                if harmonyOnly, let pref = kinds[i].preference, pref != .bothSidesFree {
                    let present = Set(kinds.map(\.id))
                    if layout.preference(pref, i, c.placement, present, layout.solidMap()) == false { ok = false }
                }
                if ok && access && kinds[i].layer == .solid && !stillUsable(depth) { ok = false }
                if ok && wantStars >= 3 && kinds[i].layer == .solid && !pocketsFillable(depth) { ok = false }
                if ok { dfs(depth + 1) }
                apply(i, c, false); chosen[i] = -1
            }
            let list = lists[i]
            if let f = fixed[i] {
                guard let ci = list.firstIndex(where: { $0.placement == f })
                        ?? list.firstIndex(where: { Set($0.cells) == Set(kinds[i].cells(at: f).map { $0.y * W + $0.x }) }) else { return }
                attempt(ci, list[ci])
                return
            }
            // identical consecutive pieces: only increasing candidate indices (no duplicate permutations)
            var start = 0
            if depth > 0, kinds[order[depth - 1]].id == kinds[i].id, fixed[order[depth - 1]] == nil { start = chosen[order[depth - 1]] + 1 }
            if start >= list.count { return }
            for ci in start..<list.count {
                attempt(ci, list[ci])
                if stop { return }
            }
        }
        dfs(0)
        return res
    }

    /// Random restarts until a layout with `stars` is found (or the deadline passes).
    public func find(stars: Int, fixed: [Int: Placement] = [:], deadline: Date, nodesPerTry: Int = 60_000) -> [Placement]? {
        var seed: UInt64 = 1
        // first a plain ordered pass, then shuffled ones
        repeat {
            let r = solve(fixed: fixed, stopAtFirst: true, wantStars: stars, seed: seed == 1 ? nil : seed, maxNodes: nodesPerTry, deadline: deadline)
            if r.bestStars >= stars { return r.best }
            if r.complete && seed == 1 && fixed.isEmpty && stars <= 1 { return nil }
            seed &+= 0x9E3779B97F4A7C15
        } while Date() < deadline
        return nil
    }

    /// ASCII plan of a layout (for the level tool and test failures).
    public func draw(_ placements: [Placement]) -> String {
        var g = [[Character]](repeating: [Character](repeating: " ", count: W), count: H)
        for c in room.floor { g[c.y][c.x] = "·" }
        for c in room.doorSwing { g[c.y][c.x] = "d" }
        for c in room.columns { g[c.y][c.x] = "X" }
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for (i, p) in placements.enumerated() where kinds[i].layer == .floor {
            for c in kinds[i].cells(at: p) where g[c.y][c.x] == "·" { g[c.y][c.x] = "~" }
            _ = i
        }
        for (i, p) in placements.enumerated() where kinds[i].layer == .solid {
            for c in kinds[i].cells(at: p) { g[c.y][c.x] = letters[i % 26] }
        }
        var s = ""
        let wl = Set(room.windowCells)
        for y in 0..<H { s += String(g[y]) + (wl.contains(where: { $0.y == y }) ? "" : "") + "\n" }
        s += zip(letters, kinds).map { "\($0)=\($1.id)" }.joined(separator: " ")
        return s
    }
}

/// Small deterministic RNG for shuffles.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(_ s: UInt64) { state = s }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
