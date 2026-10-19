import SceneKit
import UIKit
import PerfectFitCore

/// Builds the 3D model of each piece. Origin = center of the footprint on the floor, front facing +Z,
/// sized to its cells (50 cm each). Poly Haven models (Resources/Models) for the armchair, tables, bookcase,
/// dresser and plant; the rest is modeled here, like small architectural miniatures, with the same CC0 textures.
enum FurnitureModels {
    static let gap: CGFloat = 0.04   // breathing room inside the footprint

    static func node(for kind: FurnitureKind, style: RoomStyle) -> SCNNode {
        let W = CGFloat(kind.w) * CGFloat(cellSize) - gap, D = CGFloat(kind.d) * CGFloat(cellSize) - gap
        let n: SCNNode
        switch kind.id {
        case "bed_single": n = bed(W, D, style, pillows: 1)
        case "bed_double": n = bed(W, D, style, pillows: 2)
        case "nightstand": n = nightstand(W, D, style)
        case "wardrobe": n = wardrobe(W, D, style)
        case "desk": n = desk(W, D, style)
        case "chair": n = chair(W, D, style)
        case "sofa": n = sofa(W, D, style)
        case "floor_lamp": n = floorLamp(W, D)
        case "rug": n = rug(W, D, style)
        case "rug_small": n = rug(W, D, style)
        case "armchair": n = model("armchair", fit: (W, D))
        case "coffee_table": n = model("coffee_table", fit: (W, D))
        case "round_table": n = model("round_coffee_table", fit: (W, D))
        case "bookcase": n = bookcase(W, D, style)
        case "dresser": n = dresser(W, D)
        case "plant": n = model("plant", fit: (W * 1.35, D * 1.35))
        default: n = box(W, 0.5, D, mat: Mat.oak(style.wood))
        }
        n.name = kind.id
        n.enumerateHierarchy { c, _ in c.castsShadow = kind.layer == .solid }
        return n
    }

    // MARK: - building blocks

    static func box(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, mat: SCNMaterial, chamfer: CGFloat = 0.006,
                    at p: SCNVector3 = SCNVector3Zero, base: CGFloat = 0) -> SCNNode {
        let g = SCNBox(width: w, height: h, length: d, chamferRadius: min(chamfer, min(w, h, d) / 2))
        g.chamferSegmentCount = chamfer > 0.02 ? 4 : 1
        g.materials = [mat]
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(p.x, Float(base + h / 2) + p.y, p.z)
        return n
    }
    static func cyl(_ r: CGFloat, _ h: CGFloat, mat: SCNMaterial, at p: SCNVector3, base: CGFloat = 0) -> SCNNode {
        let g = SCNCylinder(radius: r, height: h); g.radialSegmentCount = 24; g.materials = [mat]
        let n = SCNNode(geometry: g); n.position = SCNVector3(p.x, Float(base + h / 2) + p.y, p.z); return n
    }
    static func group(_ parts: [SCNNode]) -> SCNNode { let n = SCNNode(); parts.forEach(n.addChildNode); return n }

    // MARK: - beds

    static func bed(_ W: CGFloat, _ D: CGFloat, _ s: RoomStyle, pillows: Int) -> SCNNode {
        let oak = Mat.oak(s.wood)
        let sheet = Mat.linen(UIColor(hex: 0xF7F3EC))
        let duvet = Mat.linen(s.duvet)
        var parts: [SCNNode] = []
        let frameH: CGFloat = 0.26, legH: CGFloat = 0.08
        // legs + frame
        for (x, z) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            parts.append(box(0.05, legH, 0.05, mat: oak, at: SCNVector3(Float(x) * Float(W / 2 - 0.06), 0, Float(z) * Float(D / 2 - 0.06))))
        }
        parts.append(box(W, frameH - legH, D - 0.04, mat: oak, chamfer: 0.012, at: SCNVector3(0, 0, 0.02), base: legH))
        // headboard (back = −Z)
        parts.append(box(W, 0.86, 0.06, mat: oak, chamfer: 0.015, at: SCNVector3(0, 0, Float(-D / 2 + 0.03))))
        parts.append(box(W - 0.08, 0.32, 0.06, mat: Mat.linen(s.fabric), chamfer: 0.03, at: SCNVector3(0, 0, Float(-D / 2 + 0.085)), base: 0.42))
        // mattress
        let mattressD = D - 0.1
        parts.append(box(W - 0.05, 0.17, mattressD, mat: sheet, chamfer: 0.05, at: SCNVector3(0, 0, 0.04), base: frameH))
        // duvet over the lower two thirds, with a folded edge
        let duvetD = mattressD * 0.66
        parts.append(box(W - 0.01, 0.05, duvetD, mat: duvet, chamfer: 0.025, at: SCNVector3(0, 0, Float(D / 2 - duvetD / 2 - 0.02)), base: frameH + 0.145))
        parts.append(box(W - 0.01, 0.06, 0.12, mat: Mat.linen(UIColor(hex: 0xF7F3EC)), chamfer: 0.03, at: SCNVector3(0, 0, Float(D / 2 - duvetD - 0.02)), base: frameH + 0.15))
        // pillows
        let pw = (W - 0.16) / CGFloat(pillows) - 0.04
        for i in 0..<pillows {
            let x = -((W - 0.16) / 2) + pw / 2 + CGFloat(i) * (pw + 0.04) + 0.02
            let p = box(pw, 0.11, 0.34, mat: sheet, chamfer: 0.05, at: SCNVector3(Float(x), 0, Float(-D / 2 + 0.3)), base: frameH + 0.16)
            p.eulerAngles.x = -0.18
            parts.append(p)
        }
        return group(parts)
    }

    // MARK: - storage

    static func nightstand(_ W: CGFloat, _ D: CGFloat, _ s: RoomStyle) -> SCNNode {
        let oak = Mat.oak(s.wood)
        var parts: [SCNNode] = []
        let w = W - 0.06, d = D - 0.12, h: CGFloat = 0.46
        parts.append(box(w, h - 0.06, d, mat: oak, chamfer: 0.01, at: SCNVector3(0, 0, Float(-D / 2 + d / 2 + 0.02)), base: 0.06))
        for (x, z) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            parts.append(box(0.03, 0.06, 0.03, mat: oak, at: SCNVector3(Float(x) * Float(w / 2 - 0.03), 0, Float(-D / 2 + d / 2 + 0.02) + Float(z) * Float(d / 2 - 0.03))))
        }
        // drawer seam and knob
        let front = Float(-D / 2 + d + 0.02)
        parts.append(box(w - 0.04, 0.004, 0.004, mat: Mat.flat(UIColor(hex: 0x5E4C3B)), at: SCNVector3(0, 0, front), base: 0.33))
        parts.append(cyl(0.012, 0.016, mat: Mat.bronze, at: SCNVector3(0, 0, front + 0.008), base: 0.38).rotatedX())
        // little lamp
        parts += tableLamp(at: SCNVector3(Float(w / 2 - 0.12), 0, Float(-D / 2 + 0.14)), base: h)
        return group(parts)
    }

    static func tableLamp(at p: SCNVector3, base: CGFloat) -> [SCNNode] {
        let foot = cyl(0.05, 0.02, mat: Mat.flat(UIColor(hex: 0xE9E2D6), roughness: 0.4), at: p, base: base)
        let stem = cyl(0.008, 0.16, mat: Mat.bronze, at: p, base: base + 0.02)
        let shadeG = SCNCone(topRadius: 0.05, bottomRadius: 0.075, height: 0.1); shadeG.radialSegmentCount = 24
        shadeG.materials = [Mat.shade(true)]
        let shade = SCNNode(geometry: shadeG); shade.position = SCNVector3(p.x, Float(base + 0.21), p.z)
        shade.name = "lampshade"
        return [foot, stem, shade]
    }

    static func wardrobe(_ W: CGFloat, _ D: CGFloat, _ s: RoomStyle) -> SCNNode {
        let oak = Mat.oak(s.wood)
        let d = D - 0.04, h: CGFloat = 2.0
        var parts: [SCNNode] = [box(W, h - 0.06, d, mat: oak, chamfer: 0.01, base: 0.06)]
        parts.append(box(W - 0.06, 0.06, d - 0.06, mat: Mat.flat(UIColor(hex: 0x4A3D31)), base: 0))
        let front = Float(d / 2)
        parts.append(box(0.004, h - 0.14, 0.004, mat: Mat.flat(UIColor(hex: 0x5E4C3B)), at: SCNVector3(0, 0, front), base: 0.1))
        for x in [-0.05, 0.05] {
            parts.append(box(0.012, 0.3, 0.02, mat: Mat.bronze, chamfer: 0.005, at: SCNVector3(Float(x), 0, front + 0.01), base: 0.95))
        }
        return group(parts)
    }

    static func dresser(_ W: CGFloat, _ D: CGFloat) -> SCNNode {
        let body = model("dresser", fit: (W, D))
        let (_, mx) = body.boundingBox
        let top = CGFloat(mx.y) * CGFloat(body.scale.y)
        let vase = model("vase", fit: (0.13, 0.13))
        vase.position = SCNVector3(Float(W / 2 - 0.15), Float(top), -0.02)
        let plant = model("succulent", fit: (0.14, 0.14))
        plant.position = SCNVector3(Float(-W / 2 + 0.16), Float(top), 0.0)
        return group([body, vase, plant])
    }

    static func bookcase(_ W: CGFloat, _ D: CGFloat, _ s: RoomStyle) -> SCNNode {
        let shelves = model("bookcase", fit: (W, D))
        // a few books in the cubbies: muted, warm spines
        let colors: [UInt32] = [0x8C6F57, 0xB7A58E, 0x6F7B73, 0xC79A7E, 0x4F5A63, 0xD8CDBB]
        var rng = SystemRandomNumberGenerator()
        var parts = [shelves]
        let (mn, mx) = shelves.boundingBox
        let sc = CGFloat(shelves.scale.x)
        let width = CGFloat(mx.x - mn.x) * sc, height = CGFloat(mx.y - mn.y) * sc
        let cubbyW = width / 3, rows: [CGFloat] = [0.43, 0.69, 0.95].map { $0 * height / 1.56 }
        for (r, y) in rows.enumerated() {
            for c in 0..<3 where (r + c) % 2 == 0 {
                var x = -width / 2 + CGFloat(c) * cubbyW + 0.04
                for _ in 0..<Int.random(in: 4...7, using: &rng) {
                    let t = CGFloat.random(in: 0.025...0.04, using: &rng), h = CGFloat.random(in: 0.15...0.21, using: &rng)
                    if x + t > -width / 2 + CGFloat(c + 1) * cubbyW - 0.04 { break }
                    parts.append(box(t, h, 0.16, mat: Mat.flat(UIColor(hex: colors.randomElement(using: &rng)!), roughness: 0.75), at: SCNVector3(Float(x + t / 2), 0, -0.02), base: y))
                    x += t + 0.004
                }
            }
        }
        return group(parts)
    }

    // MARK: - work & seats

    static func desk(_ W: CGFloat, _ D: CGFloat, _ s: RoomStyle) -> SCNNode {
        let oak = Mat.oak(s.wood)
        let d = D - 0.06, top: CGFloat = 0.74
        var parts: [SCNNode] = [box(W, 0.03, d, mat: oak, chamfer: 0.006, at: SCNVector3(0, 0, -0.01), base: top - 0.03)]
        for (x, z) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            parts.append(box(0.035, top - 0.03, 0.035, mat: oak, at: SCNVector3(Float(x) * Float(W / 2 - 0.04), 0, Float(z) * Float(d / 2 - 0.04) - 0.01)))
        }
        parts.append(box(W - 0.1, 0.07, 0.02, mat: oak, at: SCNVector3(0, 0, Float(-d / 2 + 0.03)), base: top - 0.1))
        // a closed notebook and a lamp
        parts.append(box(0.22, 0.015, 0.16, mat: Mat.flat(UIColor(hex: 0x5B6670), roughness: 0.7), at: SCNVector3(-0.05, 0, 0.03), base: top))
        parts += tableLamp(at: SCNVector3(Float(W / 2 - 0.13), 0, Float(-d / 2 + 0.1)), base: top)
        return group(parts)
    }

    static func chair(_ W: CGFloat, _ D: CGFloat, _ s: RoomStyle) -> SCNNode {
        let oak = Mat.oak(s.wood)
        let w: CGFloat = 0.4, seat: CGFloat = 0.44
        var parts: [SCNNode] = []
        for (x, z) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            parts.append(box(0.03, seat, 0.03, mat: oak, at: SCNVector3(Float(x) * Float(w / 2 - 0.03), 0, Float(z) * Float(w / 2 - 0.03))))
        }
        parts.append(box(w, 0.035, w, mat: oak, chamfer: 0.01, base: seat))
        parts.append(box(w - 0.04, 0.03, w - 0.06, mat: Mat.linen(s.fabric), chamfer: 0.012, base: seat + 0.035))
        // back on −Z (the chair faces +Z, toward the desk)
        for x in [-1.0, 1.0] { parts.append(box(0.03, 0.4, 0.03, mat: oak, at: SCNVector3(Float(x) * Float(w / 2 - 0.03), 0, Float(-w / 2 + 0.03)), base: seat)) }
        parts.append(box(w, 0.12, 0.025, mat: oak, chamfer: 0.008, at: SCNVector3(0, 0, Float(-w / 2 + 0.03)), base: seat + 0.27))
        return group(parts)
    }

    static func sofa(_ W: CGFloat, _ D: CGFloat, _ s: RoomStyle) -> SCNNode {
        let fab = Mat.boucle(s.fabric)
        let d = D - 0.08
        var parts: [SCNNode] = []
        for (x, z) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            parts.append(box(0.04, 0.08, 0.04, mat: Mat.oak(s.wood), at: SCNVector3(Float(x) * Float(W / 2 - 0.1), 0, Float(z) * Float(d / 2 - 0.08))))
        }
        parts.append(box(W, 0.2, d, mat: fab, chamfer: 0.04, base: 0.08))
        // back and arms
        parts.append(box(W, 0.5, 0.2, mat: fab, chamfer: 0.07, at: SCNVector3(0, 0, Float(-d / 2 + 0.1)), base: 0.2))
        for x in [-1.0, 1.0] { parts.append(box(0.18, 0.34, d, mat: fab, chamfer: 0.07, at: SCNVector3(Float(x) * Float(W / 2 - 0.09), 0, 0), base: 0.2)) }
        // seat cushions
        let inner = W - 0.36, n = 3
        let cw = inner / CGFloat(n) - 0.01
        for i in 0..<n {
            let x = -inner / 2 + cw / 2 + CGFloat(i) * (cw + 0.015)
            parts.append(box(cw, 0.13, d - 0.24, mat: fab, chamfer: 0.05, at: SCNVector3(Float(x), 0, 0.1), base: 0.27))
            let back = box(cw, 0.36, 0.14, mat: fab, chamfer: 0.06, at: SCNVector3(Float(x), 0, Float(-d / 2 + 0.25)), base: 0.38)
            back.eulerAngles.x = -0.12
            parts.append(back)
        }
        // throw cushion
        let c = box(0.36, 0.3, 0.1, mat: Mat.linen(s.duvet), chamfer: 0.05, at: SCNVector3(Float(W / 2 - 0.42), 0, Float(-d / 2 + 0.36)), base: 0.42)
        c.eulerAngles = SCNVector3(-0.2, 0.25, 0.08)
        parts.append(c)
        return group(parts)
    }

    static func floorLamp(_ W: CGFloat, _ D: CGFloat) -> SCNNode {
        let base = cyl(0.13, 0.025, mat: Mat.blackMetal, at: SCNVector3Zero)
        let pole = cyl(0.012, 1.38, mat: Mat.bronze, at: SCNVector3Zero, base: 0.025)
        let g = SCNCylinder(radius: 0.19, height: 0.26); g.radialSegmentCount = 32; g.materials = [Mat.shade(true)]
        let shade = SCNNode(geometry: g); shade.position = SCNVector3(0, 1.4 + 0.13, 0); shade.name = "lampshade"
        return group([base, pole, shade])
    }

    static func rug(_ W: CGFloat, _ D: CGFloat, _ s: RoomStyle) -> SCNNode {
        let r = box(W - 0.04, 0.012, D - 0.04, mat: Mat.boucle(s.rug), chamfer: 0.006)
        let border = box(W - 0.12, 0.002, D - 0.12, mat: Mat.overlay(UIColor(hex: 0xFFFFFF), alpha: 0.0), base: 0.012)
        return group([r, border])
    }

    // MARK: - Poly Haven models

    private static var modelCache: [String: SCNNode] = [:]

    /// Loads Models/<key>.scn (made by tools/assets/pipeline.swift), restores its textures, and scales it to fit.
    static func model(_ key: String, fit: (CGFloat, CGFloat)) -> SCNNode {
        let proto: SCNNode
        if let c = modelCache[key] { proto = c } else {
            guard let url = Bundle.main.url(forResource: key, withExtension: "scn", subdirectory: "Models"),
                  let scene = try? SCNScene(url: url), let root = scene.rootNode.childNodes.first else {
                return box(fit.0 * 0.8, 0.4, fit.1 * 0.8, mat: Mat.flat(.lightGray))
            }
            root.enumerateHierarchy { n, _ in
                for m in n.geometry?.materials ?? [] { restore(m) }
            }
            modelCache[key] = root
            proto = root
        }
        let n = proto.clone()
        let (mn, mx) = n.boundingBox
        let sx = fit.0 / CGFloat(mx.x - mn.x), sz = fit.1 / CGFloat(mx.z - mn.z)
        let s = Float(min(sx, sz))
        n.scale = SCNVector3(s, s, s)
        n.position = SCNVector3(-(mn.x + mx.x) / 2 * s, -mn.y * s, -(mn.z + mx.z) / 2 * s)
        return group([n])
    }

    private static func restore(_ m: SCNMaterial) {
        guard let name = m.name else { return }
        func url(_ suffix: String, _ ext: String = "jpg") -> URL? { Bundle.main.url(forResource: "\(name)_\(suffix)", withExtension: ext, subdirectory: "Models/Textures") }
        m.lightingModel = .physicallyBased
        if let d = url("diff", "png") {
            m.diffuse.contents = d
            m.isDoubleSided = true
            m.shaderModifiers = [.fragment: "if (_output.color.a < 0.5) discard_fragment();"]
        } else if let d = url("diff") { m.diffuse.contents = d }
        if let n = url("nor") { m.normal.contents = n; m.normal.intensity = 0.8 }
        if let r = url("rough") { m.roughness.contents = r } else { m.roughness.contents = 0.62 }
        if let mt = url("metal") { m.metalness.contents = mt } else { m.metalness.contents = 0 }
        for p in [m.diffuse, m.normal, m.roughness, m.metalness] { p.mipFilter = .linear; p.wrapS = .repeat; p.wrapT = .repeat }
    }
}

extension SCNNode {
    func rotatedX() -> SCNNode { eulerAngles.x = .pi / 2; return self }
}
