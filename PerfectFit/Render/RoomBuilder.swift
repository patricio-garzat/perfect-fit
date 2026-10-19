import SceneKit
import UIKit
import PerfectFitCore

/// Builds the room of a level like an architectural model: a wooden floor on a plinth, plaster walls with a
/// darker cut on top, doors drawn open with their swing arc, windows with glass and a patch of daylight.
/// The room is centered on the origin; one cell = 0.5 m; plan y → world +Z.
final class RoomBuilder {
    let room: Room
    let style: RoomStyle
    let s = CGFloat(cellSize)
    let wallT: CGFloat = 0.1
    let wallH: CGFloat = 2.4
    let base: CGFloat = 0.28     // plinth below the floor
    let ox: CGFloat, oz: CGFloat

    /// Walls that can be cut down when they face the camera.
    struct Wall { let node: SCNNode; let normal: SIMD2<Float>; let extras: [SCNNode] }
    private(set) var walls: [Wall] = []
    private(set) var doorSwingNodes: [SCNNode] = []
    let root = SCNNode()
    let grid = SCNNode()
    let overlays = SCNNode()   // zones, footprints, warnings

    init(room: Room, style: RoomStyle) {
        self.room = room
        self.style = style
        ox = -CGFloat(room.width) * CGFloat(cellSize) / 2
        oz = -CGFloat(room.height) * CGFloat(cellSize) / 2
        build()
    }

    // MARK: - coordinates

    func corner(_ x: Int, _ y: Int) -> (CGFloat, CGFloat) { (ox + CGFloat(x) * s, oz + CGFloat(y) * s) }
    func center(_ c: Cell) -> SCNVector3 { SCNVector3(Float(ox + (CGFloat(c.x) + 0.5) * s), 0, Float(oz + (CGFloat(c.y) + 0.5) * s)) }
    /// World position of a placement: the center of its rotated footprint.
    func position(_ kind: FurnitureKind, _ p: Placement) -> SCNVector3 {
        let (w, h) = kind.rotatedSize(p.rotation)
        return SCNVector3(Float(ox + (CGFloat(p.origin.x) + CGFloat(w) / 2) * s), 0, Float(oz + (CGFloat(p.origin.y) + CGFloat(h) / 2) * s))
    }
    /// Plan coordinates (in cells, fractional) of a world point.
    func plan(_ v: SCNVector3) -> (Double, Double) { (Double((CGFloat(v.x) - ox) / s), Double((CGFloat(v.z) - oz) / s)) }

    var size: (CGFloat, CGFloat) { (CGFloat(room.width) * s, CGFloat(room.height) * s) }

    // MARK: - build

    private func build() {
        root.addChildNode(floor())
        root.addChildNode(contactShadow())
        buildWalls()
        root.addChildNode(daylight())
        for c in room.columns { root.addChildNode(column(c)) }
        buildGrid()
        grid.opacity = 0
        root.addChildNode(grid)
        root.addChildNode(overlays)
    }

    private func floor() -> SCNNode {
        var v: [SCNVector3] = [], n: [SCNVector3] = [], t: [CGPoint] = [], idx: [UInt32] = []
        let tile: CGFloat = 1.6
        for c in room.floor.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
            let (x0, z0) = corner(c.x, c.y), x1 = x0 + s, z1 = z0 + s
            let b = UInt32(v.count)
            for (x, z) in [(x0, z0), (x1, z0), (x1, z1), (x0, z1)] {
                v.append(SCNVector3(Float(x), 0, Float(z))); n.append(SCNVector3(0, 1, 0)); t.append(CGPoint(x: x / tile, y: z / tile))
            }
            idx += [b, b + 2, b + 1, b, b + 3, b + 2]
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v), SCNGeometrySource(normals: n), SCNGeometrySource(textureCoordinates: t)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = Mat.floor(style.floorTint).copy() as! SCNMaterial
        for p in [m.diffuse, m.normal, m.roughness] { p.contentsTransform = SCNMatrix4Identity }
        g.materials = [m]
        let node = SCNNode(geometry: g)
        node.name = "floor"
        return node
    }

    /// Soft shadow under the floating model.
    private func contactShadow() -> SCNNode {
        let (w, d) = size
        let plane = SCNPlane(width: w + 2.2, height: d + 2.2)
        let r = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256))
        let img = r.image { ctx in
            let colors = [UIColor(white: 0, alpha: 0.30).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.45, 1])!
            ctx.cgContext.drawRadialGradient(grad, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
        }
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = img; m.writesToDepthBuffer = false; m.blendMode = .alpha
        plane.materials = [m]
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position.y = Float(-base - 0.02)
        n.castsShadow = false
        n.renderingOrder = -10
        return n
    }

    private enum EdgeKind: Equatable { case wall, door(Int), window(Int) }

    private func buildWalls() {
        // boundary edges, grouped by side and line
        struct Edge { let side: Side; let line: Int; let at: Int; let kind: EdgeKind }
        var edges: [Edge] = []
        var openingKind: [String: EdgeKind] = [:]
        for (i, d) in room.doors.enumerated() { for c in d.cells { openingKind["\(c.x),\(c.y),\(d.side.rawValue)"] = .door(i) } }
        for (i, w) in room.windows.enumerated() { for c in w.cells { openingKind["\(c.x),\(c.y),\(w.side.rawValue)"] = .window(i) } }
        for c in room.floor {
            for side in Side.allCases where !room.floor.contains(c + side.outward) {
                let k = openingKind["\(c.x),\(c.y),\(side.rawValue)"] ?? .wall
                switch side {
                case .north: edges.append(Edge(side: side, line: c.y, at: c.x, kind: k))
                case .south: edges.append(Edge(side: side, line: c.y + 1, at: c.x, kind: k))
                case .west: edges.append(Edge(side: side, line: c.x, at: c.y, kind: k))
                case .east: edges.append(Edge(side: side, line: c.x + 1, at: c.y, kind: k))
                }
            }
        }
        // runs of the same kind
        let groups = Dictionary(grouping: edges) { "\($0.side.rawValue)|\($0.line)" }
        for (_, list) in groups {
            let sorted = list.sorted { $0.at < $1.at }
            var runStart = sorted[0], prev = sorted[0]
            func flush(_ a: Edge, _ b: Edge) { addRun(side: a.side, line: a.line, from: a.at, to: b.at + 1, kind: a.kind) }
            for e in sorted.dropFirst() {
                if e.at == prev.at + 1 && e.kind == prev.kind { prev = e; continue }
                flush(runStart, prev); runStart = e; prev = e
            }
            flush(runStart, prev)
        }
        // posts on outer corners
        for y in 0...room.height { for x in 0...room.width {
            let quad = [Cell(x - 1, y - 1), Cell(x, y - 1), Cell(x - 1, y), Cell(x, y)].map(room.floor.contains)
            guard quad.filter({ $0 }).count == 1, let i = quad.firstIndex(of: true) else { continue }
            let (cx, cz) = corner(x, y)
            let dx: CGFloat = (i == 0 || i == 2) ? 1 : -1, dz: CGFloat = (i == 0 || i == 1) ? 1 : -1
            let post = wallBox(length: wallT, alongX: true)
            post.position = SCNVector3(Float(cx + dx * wallT / 2), Float(-base), Float(cz + dz * wallT / 2))
            let normal = SIMD2<Float>(Float(dx), Float(dz)) / sqrt(2)
            root.addChildNode(post)
            walls.append(Wall(node: post, normal: normal, extras: []))
        }}
    }

    /// A plaster wall block from the plinth bottom up to `wallH`, pivot at its bottom center.
    private func wallBox(length: CGFloat, alongX: Bool, from y0: CGFloat = 0, to y1: CGFloat? = nil) -> SCNNode {
        let top = y1 ?? wallH
        let h = top - y0 + (y0 == 0 ? base : 0)
        let g = SCNBox(width: alongX ? length : wallT, height: h, length: alongX ? wallT : length, chamferRadius: 0)
        let plaster = Mat.plaster(style.wall)
        let cap = Mat.flat(style.wallCap, roughness: 0.9)
        g.materials = [plaster, plaster, plaster, plaster, cap, plaster]
        let inner = SCNNode(geometry: g)
        inner.position.y = Float(h / 2)
        let n = SCNNode()
        n.addChildNode(inner)
        n.castsShadow = true
        return n
    }

    private func addRun(side: Side, line: Int, from a: Int, to b: Int, kind: EdgeKind) {
        let alongX = side == .north || side == .south
        let len = CGFloat(b - a) * s
        let lineCoord = CGFloat(line) * s + (alongX ? oz : ox)
        let off: CGFloat = (side == .north || side == .west) ? -wallT / 2 : wallT / 2
        let mid = (alongX ? ox : oz) + (CGFloat(a) + CGFloat(b - a) / 2) * s
        let p = alongX ? SCNVector3(Float(mid), Float(-base), Float(lineCoord + off)) : SCNVector3(Float(lineCoord + off), Float(-base), Float(mid))
        let normal = SIMD2<Float>(Float(side.outward.x), Float(side.outward.y))
        let holder = SCNNode(); holder.position = p
        var extras: [SCNNode] = []
        switch kind {
        case .wall:
            holder.addChildNode(wallBox(length: len, alongX: alongX))
        case .door(let i):
            let d = room.doors[i]
            // header above the opening + a slim threshold
            let header = wallBox(length: len, alongX: alongX, from: 2.1)
            header.position.y = Float(base + 2.1)
            holder.addChildNode(header)
            holder.addChildNode(wallBox(length: len, alongX: alongX, from: 0, to: 0.0))
            extras += door(holder: holder, length: len, alongX: alongX, side: side, opening: d)
        case .window:
            holder.addChildNode(wallBox(length: len, alongX: alongX, from: 0, to: 0.85))
            let header = wallBox(length: len, alongX: alongX, from: 2.15)
            header.position.y = Float(base + 2.15)
            holder.addChildNode(header)
            extras += window(holder: holder, length: len, alongX: alongX)
        }
        root.addChildNode(holder)
        walls.append(Wall(node: holder, normal: normal, extras: extras))
    }

    /// Door frame, the leaf open ~80° into the room and the swing arc drawn on the floor (plan style).
    /// Built in world coordinates; the frame and leaf hide when their wall is cut toward the camera.
    private func door(holder: SCNNode, length: CGFloat, alongX: Bool, side: Side, opening: Opening) -> [SCNNode] {
        let oak = Mat.oak(style.wood)
        let frame = Mat.flat(UIColor(hex: 0xF4F0EA), roughness: 0.6)
        var out: [SCNNode] = []
        let along = SIMD2<Float>(Float(side.along.x), Float(side.along.y))
        let inward = SIMD2<Float>(Float(-side.outward.x), Float(-side.outward.y))
        let c0 = opening.cells[0]
        // start of the opening on the inner face of the wall
        var start: SIMD2<Float>
        switch side {
        case .north: start = SIMD2(Float(ox + CGFloat(c0.x) * s), Float(oz + CGFloat(c0.y) * s))
        case .south: start = SIMD2(Float(ox + CGFloat(c0.x) * s), Float(oz + CGFloat(c0.y + 1) * s))
        case .west: start = SIMD2(Float(ox + CGFloat(c0.x) * s), Float(oz + CGFloat(c0.y) * s))
        case .east: start = SIMD2(Float(ox + CGFloat(c0.x + 1) * s), Float(oz + CGFloat(c0.y) * s))
        }
        let L = Float(length)
        // jambs at both ends, through the wall
        for t in [Float(0.02), L - 0.02] {
            let p = start + along * t - inward * Float(wallT / 2)
            let j = FurnitureModels.box(alongX ? 0.04 : wallT + 0.02, 2.1, alongX ? wallT + 0.02 : 0.04, mat: frame)
            j.position = SCNVector3(p.x, j.position.y, p.y)
            root.addChildNode(j); out.append(j)
        }
        // leaf, hinged at the start, open toward the room
        let hingeP = start + along * 0.05 + inward * 0.02
        let theta: Float = 80 * .pi / 180
        let dir = simd_normalize(along * cos(theta) + inward * sin(theta))
        let leafW = CGFloat(L - 0.1)
        let leaf = FurnitureModels.box(leafW, 2.04, 0.04, mat: oak, chamfer: 0.008)
        leaf.position = SCNVector3(Float(leafW / 2), leaf.position.y, 0)
        let knob = FurnitureModels.cyl(0.018, 0.05, mat: Mat.bronze, at: SCNVector3(Float(leafW / 2 - 0.07), 0, 0.03), base: 1.0 - 1.02).rotatedX()
        leaf.addChildNode(knob)
        let hinge = SCNNode()
        hinge.position = SCNVector3(hingeP.x, 0, hingeP.y)
        hinge.eulerAngles.y = atan2(-dir.y, dir.x)
        hinge.addChildNode(leaf)
        root.addChildNode(hinge); out.append(hinge)

        // swing arc: a thin ring from the closed position to fully open
        let r = L - 0.06, w: Float = 0.012
        var v: [SCNVector3] = [], idx: [UInt32] = []
        let steps = 28
        for k in 0...steps {
            let a = Float(k) / Float(steps) * .pi / 2
            let d = along * cos(a) + inward * sin(a)
            let o = hingeP + d * r, i = hingeP + d * (r - w)
            v.append(SCNVector3(o.x, 0.004, o.y)); v.append(SCNVector3(i.x, 0.004, i.y))
            if k > 0 { let b = UInt32(k * 2); idx += [b - 2, b - 1, b, b - 1, b + 1, b] }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.materials = [Mat.overlay(Hue.ink, alpha: 0.3)]
        let arc = SCNNode(geometry: g)
        arc.renderingOrder = 5
        arc.castsShadow = false
        root.addChildNode(arc)
        doorSwingNodes.append(arc)

        // swing area, tinted when something stands in it
        for c in opening.cells {
            for k in 0..<opening.width {
                let cell = Cell(c.x - opening.side.outward.x * k, c.y - opening.side.outward.y * k)
                guard room.floor.contains(cell) else { continue }
                let q = SCNNode(geometry: SCNPlane(width: s - 0.02, height: s - 0.02))
                q.geometry!.materials = [Mat.overlay(Hue.terracotta, alpha: 0.0)]
                q.eulerAngles.x = -.pi / 2
                q.position = center(cell); q.position.y = 0.003
                q.name = "swing:\(cell.x),\(cell.y)"
                q.renderingOrder = 4
                overlays.addChildNode(q)
            }
        }
        return out
    }

    private func window(holder: SCNNode, length: CGFloat, alongX: Bool) -> [SCNNode] {
        let frameM = Mat.flat(UIColor(hex: 0xF4F0EA), roughness: 0.55)
        var out: [SCNNode] = []
        let y0 = base + 0.85, h: CGFloat = 1.3
        let glass = FurnitureModels.box(alongX ? length - 0.04 : 0.015, h, alongX ? 0.015 : length - 0.04, mat: Mat.glass, chamfer: 0)
        glass.position.y = Float(y0 + h / 2)
        glass.castsShadow = false
        holder.addChildNode(glass); out.append(glass)
        // frame: sill, head, jambs and a center mullion
        let parts: [(CGFloat, CGFloat, CGFloat)] = [(0, y0 - 0.02, 0.05), (0, y0 + h - 0.03, 0.05)]
        for (_, y, t) in parts {
            let b = FurnitureModels.box(alongX ? length : wallT + 0.04, t, alongX ? wallT + 0.04 : length, mat: frameM)
            b.position.y = Float(y); holder.addChildNode(b); out.append(b)
        }
        for e in [-1.0, 0.0, 1.0] {
            let along = Float(e) * Float(length / 2 - (e == 0 ? 0 : 0.02))
            let m = FurnitureModels.box(alongX ? 0.035 : wallT * 0.6, h, alongX ? wallT * 0.6 : 0.035, mat: frameM)
            m.position = alongX ? SCNVector3(along, Float(y0 + h / 2), 0) : SCNVector3(0, Float(y0 + h / 2), along)
            holder.addChildNode(m); out.append(m)
        }
        return out
    }

    /// Patch of warm daylight on the floor in front of each window (also where tall pieces can't go).
    private func daylight() -> SCNNode {
        let n = SCNNode()
        let r = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let img = r.image { ctx in
            let colors = [UIColor(hex: 0xFFF3D6, alpha: 0.55).cgColor, UIColor(hex: 0xFFF3D6, alpha: 0.0).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(grad, start: CGPoint(x: 32, y: 0), end: CGPoint(x: 32, y: 64), options: [])
        }
        for w in room.windows {
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = img; m.blendMode = .add; m.writesToDepthBuffer = false
            let len = CGFloat(w.width) * s
            let depth = s * 1.6
            let p = SCNNode(geometry: SCNPlane(width: len, height: depth))
            p.geometry!.materials = [m]
            let first = center(w.cells[0]), last = center(w.cells[w.cells.count - 1])
            let mid = SCNVector3((first.x + last.x) / 2, 0.002, (first.z + last.z) / 2)
            let inward = SIMD2<Float>(Float(-w.side.outward.x), Float(-w.side.outward.y))
            // start at the wall, fade into the room
            p.position = SCNVector3(mid.x + inward.x * Float(depth / 2 - s / 2), 0.002, mid.z + inward.y * Float(depth / 2 - s / 2))
            p.eulerAngles.x = -.pi / 2
            // plane +Y (top of the gradient, brightest) must point to the window
            p.eulerAngles.y = atan2(-inward.x, -inward.y) + .pi
            p.renderingOrder = 3
            p.castsShadow = false
            n.addChildNode(p)
        }
        return n
    }

    private func column(_ c: Cell) -> SCNNode {
        let n = wallBox(length: s, alongX: true)
        (n.childNodes[0].geometry as! SCNBox).length = s
        let p = center(c)
        n.position = SCNVector3(p.x, Float(-base), p.z)
        return n
    }

    private func buildGrid() {
        var v: [SCNVector3] = [], idx: [UInt32] = []
        let t: Float = 0.006
        func seg(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
            let ax = Float(a.0), az = Float(a.1), bx = Float(b.0), bz = Float(b.1)
            let dx = bx - ax, dz = bz - az, l = sqrt(dx * dx + dz * dz)
            let nx = -dz / l * t, nz = dx / l * t
            let i = UInt32(v.count)
            v += [SCNVector3(ax + nx, 0, az + nz), SCNVector3(bx + nx, 0, bz + nz), SCNVector3(bx - nx, 0, bz - nz), SCNVector3(ax - nx, 0, az - nz)]
            idx += [i, i + 1, i + 2, i, i + 2, i + 3]
        }
        for c in room.floor {
            let (x0, z0) = corner(c.x, c.y)
            seg((x0, z0), (x0 + s, z0)); seg((x0, z0), (x0, z0 + s))
            if !room.floor.contains(Cell(c.x + 1, c.y)) { seg((x0 + s, z0), (x0 + s, z0 + s)) }
            if !room.floor.contains(Cell(c.x, c.y + 1)) { seg((x0, z0 + s), (x0 + s, z0 + s)) }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.materials = [Mat.overlay(Hue.ink, alpha: 0.13)]
        grid.geometry = g
        grid.position.y = 0.0035
        grid.renderingOrder = 6
        grid.castsShadow = false
    }
}
