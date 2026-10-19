// Perfect Fit · asset pipeline (macOS).
// Converts the Poly Haven USD downloads in assets-src/ into light SceneKit files for the app:
// Y-up, meters, centered on the floor, front facing +Z, our own PBR materials (JPG only, no EXR).
//
//   swiftc -O tools/assets/pipeline.swift -o /tmp/pf-pipeline
//   /tmp/pf-pipeline preview <out.png>      contact sheet of every source model (for picking yaw/variants)
//   /tmp/pf-pipeline build                  writes PerfectFit/Resources/Models/*.scn + textures
//
// Run from the PerfectFit/ folder.
import SceneKit
import ModelIO
import AppKit
import ImageIO
import UniformTypeIdentifiers

let src = URL(fileURLWithPath: "assets-src/polyhaven/models")
let out = URL(fileURLWithPath: "PerfectFit/Resources/Models")

struct Spec {
    let key: String        // name used by the game catalog
    let source: String     // Poly Haven asset id
    var yaw: Float = 0     // degrees, applied after Y-up so the front faces +Z
    var children: [Int]? = nil  // keep only these meshes (packs with several variants)
    var texSize = 1024
}

// Picked on the preview sheet: only the pieces that fit a warm, contemporary room.
// Fronts already face +Z. Beds, wardrobes, sofas, desks, chairs, rugs, lamps, doors and
// windows are modeled in code by the game (FurnitureModels.swift) with the CC0 textures below.
let specs: [Spec] = [
    Spec(key: "armchair", source: "mid_century_lounge_chair"),
    Spec(key: "coffee_table", source: "modern_coffee_table_01"),
    Spec(key: "round_coffee_table", source: "coffee_table_round_01"),
    Spec(key: "bookcase", source: "wooden_display_shelves_01"),
    Spec(key: "dresser", source: "vintage_wooden_drawer_01"),
    Spec(key: "succulent", source: "potted_plant_04", texSize: 512),
    Spec(key: "plant_pot", source: "potted_plant_04", children: [0, 1, 3], texSize: 512),
    Spec(key: "plant_leaves", source: "calathea_orbifolia_01", children: [0]),
    Spec(key: "vase", source: "ceramic_vase_01", texSize: 512),
]

/// Models made of several sources: (key, [(part, scale, lift in meters)]).
let composites: [(String, [(String, Float, Float)])] = [
    // floor plant: the white pot scaled to ~38 cm, the calathea on top
    ("plant", [("plant_pot", 2.4, 0), ("plant_leaves", 1.25, 0.30)]),
]

// MARK: - textures

func files(_ dir: URL) -> [URL] { (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] }
func find(_ dir: URL, _ tags: [String]) -> URL? {
    let all = files(dir.appendingPathComponent("textures")) + files(dir.appendingPathComponent("jpg"))
    // prefer JPG/PNG over EXR
    let hits = all.filter { u in tags.contains { u.lastPathComponent.contains("_\($0)_") } }
    return hits.first { $0.pathExtension != "exr" } ?? hits.first
}

func cgImage(_ url: URL) -> CGImage? {
    guard let s = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(s, 0, nil)
}

/// Redraws any image (EXR included) as 8-bit, optionally resized, and writes JPG (or PNG when it needs alpha).
func writeImage(_ img: CGImage, to url: URL, size: Int, gray: Bool = false, alpha: Bool = false) {
    let w = min(size, img.width), h = min(size, img.height)
    let cs = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
    let info: UInt32 = gray ? CGImageAlphaInfo.none.rawValue : (alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: info)!
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let type = alpha ? UTType.png : UTType.jpeg
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

/// Mean value of a grayscale map (to skip metal maps that are all zero).
func mean(_ img: CGImage) -> Double {
    let w = 64, h = 64
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    var s = 0; for i in 0..<(w * h) { s += Int(p[i]) }
    return Double(s) / Double(w * h) / 255
}

/// Diffuse with the alpha mask baked in (for leaves).
func withAlpha(_ diff: CGImage, _ mask: CGImage) -> CGImage {
    let w = diff.width, h = diff.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.clip(to: CGRect(x: 0, y: 0, width: w, height: h), mask: mask)
    ctx.draw(diff, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

// MARK: - model

struct Built { let node: SCNNode; let size: SCNVector3 }

func load(_ spec: Spec, texDir: URL?) -> Built {
    let dir = src.appendingPathComponent(spec.source)
    let usd = files(dir).first { $0.pathExtension == "usdc" }!
    let asset = MDLAsset(url: usd)

    // material
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.name = spec.key
    let prefix = spec.key
    func tex(_ tags: [String], _ suffix: String, gray: Bool = false) -> URL? {
        guard let u = find(dir, tags), let img = cgImage(u) else { return nil }
        guard let texDir else { return u }
        let dest = texDir.appendingPathComponent("\(prefix)_\(suffix).jpg")
        writeImage(img, to: dest, size: spec.texSize, gray: gray)
        return dest
    }
    var alphaLeaves = false
    if let d = find(dir, ["diff"]), let dimg = cgImage(d) {
        if let a = find(dir, ["alpha"]), let aimg = cgImage(a) {
            alphaLeaves = true
            if let texDir {
                let dest = texDir.appendingPathComponent("\(prefix)_diff.png")
                writeImage(withAlpha(dimg, aimg), to: dest, size: spec.texSize, alpha: true)
                m.diffuse.contents = dest
            } else { m.diffuse.contents = withAlpha(dimg, aimg) }
        } else { m.diffuse.contents = tex(["diff"], "diff") }
    }
    m.normal.contents = tex(["nor_gl"], "nor")
    // some Poly Haven roughness maps are EXR types ImageIO can't read: fall back to a soft satin value
    m.roughness.contents = tex(["rough", "roughness"], "rough", gray: true) ?? NSNumber(value: 0.62)
    if let mu = find(dir, ["metal", "metallic"]), let mimg = cgImage(mu), mean(mimg) > 0.02 {
        m.metalness.contents = tex(["metal", "metallic"], "metal", gray: true)
    } else { m.metalness.contents = NSNumber(value: 0) }
    for p in [m.diffuse, m.normal, m.roughness, m.metalness] {
        p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear
    }
    if alphaLeaves {
        m.isDoubleSided = true
        m.shaderModifiers = [.fragment: "if (_output.color.a < 0.5) discard_fragment();"]
    }

    // geometry: bake every mesh into one triangle soup in world space, then normalize
    var meshes: [MDLMesh] = []
    func walk(_ o: MDLObject) { if let m = o as? MDLMesh { meshes.append(m) }; for c in o.children.objects { walk(c) } }
    for i in 0..<asset.count { walk(asset.object(at: i)) }
    if let c = spec.children { meshes = c.map { meshes[$0] } }
    // Z-up → Y-up, then the per-model yaw
    let zup = simd_float4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 0, -1, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 0, 1))
    let yaw = simd_quatf(angle: spec.yaw * .pi / 180, axis: SIMD3(0, 1, 0))
    var P: [SIMD3<Float>] = [], N: [SIMD3<Float>] = [], T: [SIMD2<Float>] = [], I: [UInt32] = []
    for mesh in meshes {
        let wt = zup * MDLTransform.globalTransform(with: mesh, atTime: 0)
        let r3 = simd_float3x3(SIMD3(wt.columns.0.x, wt.columns.0.y, wt.columns.0.z), SIMD3(wt.columns.1.x, wt.columns.1.y, wt.columns.1.z), SIMD3(wt.columns.2.x, wt.columns.2.y, wt.columns.2.z))
        let nt = r3.inverse.transpose
        let pos = attr(mesh, MDLVertexAttributePosition, 3)
        let nor = attr(mesh, MDLVertexAttributeNormal, 3)
        let tc = attr(mesh, MDLVertexAttributeTextureCoordinate, 2)
        let base = UInt32(P.count)
        for i in 0..<mesh.vertexCount {
            let p = pos[i]
            let w = wt * SIMD4(p[0], p[1], p[2], 1)
            P.append(yaw.act(SIMD3(w.x, w.y, w.z)))
            N.append(i < nor.count ? simd_normalize(yaw.act(nt * SIMD3(nor[i][0], nor[i][1], nor[i][2]))) : SIMD3(0, 1, 0))
            T.append(i < tc.count ? SIMD2(tc[i][0], 1 - tc[i][1]) : .zero)
        }
        for case let sm as MDLSubmesh in mesh.submeshes ?? [] {
            precondition(sm.geometryType == .triangles, "geometry type \(sm.geometryType.rawValue)")
            let buf = sm.indexBuffer(asIndexType: .uInt32).map()
            let ptr = buf.bytes.bindMemory(to: UInt32.self, capacity: sm.indexCount)
            for k in 0..<sm.indexCount { I.append(ptr[k] + base) }
        }
    }
    var mn = SIMD3<Float>(repeating: .greatestFiniteMagnitude), mx = -mn
    for p in P { mn = simd_min(mn, p); mx = simd_max(mx, p) }
    let c = SIMD3((mn.x + mx.x) / 2, mn.y, (mn.z + mx.z) / 2)
    let verts = P.map { SCNVector3($0 - c) }
    let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: N.map { SCNVector3($0) }),
                                    SCNGeometrySource(textureCoordinates: T.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })],
                          elements: [SCNGeometryElement(indices: I, primitiveType: .triangles)])
    geo.materials = [m]
    geo.name = spec.key
    let node = SCNNode(geometry: geo)
    node.name = spec.key
    let sz = mx - mn
    return Built(node: node, size: SCNVector3(sz.x, sz.y, sz.z))
}

func attr(_ m: MDLMesh, _ name: String, _ n: Int) -> [[Float]] {
    guard let d = m.vertexAttributeData(forAttributeNamed: name, as: n == 3 ? .float3 : .float2) else { return [] }
    var r: [[Float]] = []
    for v in 0..<m.vertexCount {
        let p = (d.dataStart + v * d.stride).assumingMemoryBound(to: Float.self)
        r.append((0..<n).map { p[$0] })
    }
    return r
}

// MARK: - preview sheet

func render(_ node: SCNNode, size: CGFloat) -> NSImage {
    let scene = SCNScene()
    scene.background.contents = NSColor(calibratedWhite: 0.93, alpha: 1)
    scene.rootNode.addChildNode(node)
    let (mn, mx) = node.boundingBox
    let r = max(mx.x - mn.x, mx.y - mn.y, mx.z - mn.z)
    let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.usesOrthographicProjection = true
    cam.camera!.orthographicScale = Double(r) * 0.75; cam.camera!.zNear = 0.001
    // three-quarter view from the front-right, so the +Z face is visible
    cam.position = SCNVector3(r * 1.2, r * 1.0, r * 2.0)
    cam.look(at: SCNVector3(0, (mx.y - mn.y) / 2, 0))
    scene.rootNode.addChildNode(cam)
    let l = SCNNode(); l.light = SCNLight(); l.light!.type = .directional; l.light!.intensity = 900
    l.eulerAngles = SCNVector3(-0.9, 0.5, 0); scene.rootNode.addChildNode(l)
    let a = SCNNode(); a.light = SCNLight(); a.light!.type = .ambient; a.light!.intensity = 500; scene.rootNode.addChildNode(a)
    // +Z marker: a small red bar in front of the model
    let bar = SCNNode(geometry: SCNBox(width: r * 0.3, height: 0.01, length: 0.03, chamferRadius: 0))
    bar.geometry!.firstMaterial!.diffuse.contents = NSColor.red
    bar.position = SCNVector3(0, 0, mx.z + 0.08); scene.rootNode.addChildNode(bar)
    let rr = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    rr.scene = scene; rr.pointOfView = cam
    return rr.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
}

func preview(_ path: String) {
    let cell: CGFloat = 320, cols = 4
    let rows = (specs.count + cols - 1) / cols
    let sheet = NSImage(size: NSSize(width: cell * CGFloat(cols), height: (cell + 24) * CGFloat(rows)))
    var tiles: [(NSImage, String)] = []
    for s in specs {
        let b = load(s, texDir: nil)
        tiles.append((render(b.node, size: cell), String(format: "%@  %.2f×%.2f×%.2f", s.key, b.size.x, b.size.y, b.size.z)))
    }
    sheet.lockFocus()
    NSColor.white.setFill(); NSRect(origin: .zero, size: sheet.size).fill()
    for (i, t) in tiles.enumerated() {
        let x = CGFloat(i % cols) * cell, y = sheet.size.height - CGFloat(i / cols + 1) * (cell + 24)
        t.0.draw(in: NSRect(x: x, y: y + 24, width: cell, height: cell))
        (t.1 as NSString).draw(at: NSPoint(x: x + 6, y: y + 4), withAttributes: [.font: NSFont.systemFont(ofSize: 13)])
    }
    sheet.unlockFocus()
    let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote", path)
}

// MARK: - build

func build() {
    let tdir = out.appendingPathComponent("Textures")
    try? FileManager.default.removeItem(at: out)
    try! FileManager.default.createDirectory(at: tdir, withIntermediateDirectories: true)
    var manifest: [String: [String: Double]] = [:]
    for s in specs {
        let b = load(s, texDir: tdir)
        // texture paths relative to the .scn so SceneKit finds them inside the app bundle
        b.node.enumerateHierarchy { n, _ in
            for m in n.geometry?.materials ?? [] {
                for p in [m.diffuse, m.normal, m.roughness, m.metalness] {
                    if let u = p.contents as? URL { p.contents = "Textures/" + u.lastPathComponent }
                }
            }
        }
        let scene = SCNScene(); scene.rootNode.addChildNode(b.node)
        let url = out.appendingPathComponent("\(s.key).scn")
        guard scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) else { fatalError("write \(url)") }
        manifest[s.key] = ["w": Double(b.size.x), "h": Double(b.size.y), "d": Double(b.size.z)]
        print(s.key, String(format: "%.2f × %.2f × %.2f m", b.size.x, b.size.y, b.size.z))
    }
    for (key, parts) in composites {
        let node = SCNNode(); node.name = key
        for (part, scale, lift) in parts {
            let u = out.appendingPathComponent("\(part).scn")
            let p = try! SCNScene(url: u).rootNode.childNodes[0].clone()
            p.scale = SCNVector3(scale, scale, scale); p.position.y = CGFloat(lift)
            node.addChildNode(p)
            try? FileManager.default.removeItem(at: u); manifest[part] = nil
        }
        let (mn, mx) = node.boundingBox
        let scene = SCNScene(); scene.rootNode.addChildNode(node)
        _ = scene.write(to: out.appendingPathComponent("\(key).scn"), options: nil, delegate: nil, progressHandler: nil)
        manifest[key] = ["w": Double(mx.x - mn.x), "h": Double(mx.y - mn.y), "d": Double(mx.z - mn.z)]
        print(key, String(format: "%.2f × %.2f × %.2f m", mx.x - mn.x, mx.y - mn.y, mx.z - mn.z))
    }
    let data = try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: out.appendingPathComponent("models.json"))
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "preview": preview(args.count > 2 ? args[2] : "/tmp/pf-models.png")
case "build": build()
case "variants":
    // every mesh of one source, one tile each:  variants <source> <out.png>
    var tiles: [NSImage] = []
    for c in 0..<20 {
        let a = MDLAsset(url: files(src.appendingPathComponent(args[2])).first { $0.pathExtension == "usdc" }!)
        var n = 0; func walk(_ o: MDLObject) { if o is MDLMesh { n += 1 }; for k in o.children.objects { walk(k) } }
        for i in 0..<a.count { walk(a.object(at: i)) }
        if c >= n { break }
        let b = load(Spec(key: "v\(c)", source: args[2], children: [c]), texDir: nil)
        print(c, b.size); tiles.append(render(b.node, size: 300))
    }
    let sheet = NSImage(size: NSSize(width: 300 * tiles.count, height: 300)); sheet.lockFocus()
    for (i, t) in tiles.enumerated() { t.draw(in: NSRect(x: i * 300, y: 0, width: 300, height: 300)) }
    sheet.unlockFocus()
    try! NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
default: print("usage: pipeline preview <out.png> | build")
}
