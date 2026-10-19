import SceneKit
import UIKit

/// Look of a room: floor, walls and textile accent. Levels pick one by name ("oak", "linen", "walnut").
struct RoomStyle {
    let floorTint: UIColor
    let wall: UIColor
    let wallCap: UIColor
    let duvet: UIColor
    let fabric: UIColor     // sofa, cushions
    let rug: UIColor
    let wood: UIColor       // tint for our own oak furniture

    static func named(_ n: String) -> RoomStyle {
        switch n {
        case "linen":
            return RoomStyle(floorTint: UIColor(hex: 0xFFF4E6), wall: UIColor(hex: 0xE2DBD1), wallCap: UIColor(hex: 0x8B7F72),
                             duvet: UIColor(hex: 0xD9A58C), fabric: UIColor(hex: 0xE4DACB), rug: UIColor(hex: 0xC9B79E), wood: UIColor(hex: 0xFFF6EA))
        case "walnut":
            return RoomStyle(floorTint: UIColor(hex: 0xB08A68), wall: UIColor(hex: 0xE5E2DD), wallCap: UIColor(hex: 0x6D6157),
                             duvet: UIColor(hex: 0x7D8FA0), fabric: UIColor(hex: 0xC9C1B4), rug: UIColor(hex: 0x8E7C6A), wood: UIColor(hex: 0xB89272))
        default: // oak
            return RoomStyle(floorTint: UIColor(hex: 0xFFFFFF), wall: UIColor(hex: 0xE6E1DA), wallCap: UIColor(hex: 0x7E746A),
                             duvet: UIColor(hex: 0xA9B8A0), fabric: UIColor(hex: 0xE6DED2), rug: UIColor(hex: 0xD8CBB8), wood: UIColor(hex: 0xFFFFFF))
        }
    }
}

/// PBR materials made from the CC0 textures in Resources/Textures. Shared instances keep draw calls and memory low.
enum Mat {
    private static var cache: [String: SCNMaterial] = [:]

    static func texture(_ name: String) -> URL? { Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Textures") }

    /// - Parameters: tile = meters covered by one repeat of the texture.
    /// - Parameters: detailOnly = keep the texture's relief (normal, roughness) but paint it flat with `tint`
    ///   (fabrics and plaster: their photos have their own color, which fought with the room palette).
    static func pbr(_ key: String, tex: String?, tint: UIColor = .white, roughness: CGFloat? = nil, metal: CGFloat = 0,
                    tile: CGFloat = 1, normal: CGFloat = 0.6, detailOnly: Bool = false) -> SCNMaterial {
        let id = "\(key)|\(tint.description)"
        if let m = cache[id] { return m }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.name = key
        if let tex, let d = texture("\(tex)_diff") {
            if detailOnly { m.diffuse.contents = tint } else { m.diffuse.contents = d; m.multiply.contents = tint }
            if let n = texture("\(tex)_nor_gl") { m.normal.contents = n; m.normal.intensity = normal }
            if roughness == nil, let r = texture("\(tex)_rough") { m.roughness.contents = r }
        } else {
            m.diffuse.contents = tint
        }
        if let roughness { m.roughness.contents = roughness }
        m.metalness.contents = metal
        let s = SCNMatrix4MakeScale(Float(1 / tile), Float(1 / tile), 1)
        for p in [m.diffuse, m.normal, m.roughness, m.multiply] {
            p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear
            p.contentsTransform = s
        }
        m.multiply.contentsTransform = SCNMatrix4Identity
        cache[id] = m
        return m
    }

    static func oak(_ tint: UIColor = .white) -> SCNMaterial { pbr("oak", tex: "white_oak_veneer", tint: tint, tile: 0.8, normal: 0.4) }
    static func linen(_ tint: UIColor) -> SCNMaterial { pbr("linen", tex: "rough_linen", tint: tint, tile: 0.35, normal: 0.9, detailOnly: true) }
    static func boucle(_ tint: UIColor) -> SCNMaterial { pbr("boucle", tex: "wool_boucle", tint: tint, tile: 0.3, normal: 1.0, detailOnly: true) }
    static func plaster(_ tint: UIColor) -> SCNMaterial { pbr("plaster", tex: "white_plaster_02", tint: tint, roughness: 0.92, tile: 1.6, normal: 0.35, detailOnly: true) }
    static func floor(_ tint: UIColor) -> SCNMaterial { pbr("floor", tex: "wood_floor", tint: tint, tile: 1.6, normal: 0.5) }
    static func flat(_ c: UIColor, roughness: CGFloat = 0.8, metal: CGFloat = 0) -> SCNMaterial {
        pbr("flat", tex: nil, tint: c, roughness: roughness, metal: metal)
    }
    static var bronze: SCNMaterial { flat(UIColor(hex: 0x6E5A44), roughness: 0.45, metal: 0.85) }
    static var blackMetal: SCNMaterial { flat(UIColor(hex: 0x2B2825), roughness: 0.5, metal: 0.6) }
    static var glass: SCNMaterial {
        if let m = cache["glass"] { return m }
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(hex: 0xDDEBF2, alpha: 0.35)
        m.roughness.contents = 0.05
        m.metalness.contents = 0.0
        m.transparencyMode = .dualLayer
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        cache["glass"] = m
        return m
    }
    /// Warm glowing lampshade.
    static func shade(_ on: Bool) -> SCNMaterial {
        let m = linen(UIColor(hex: 0xF5EBDD)).copy() as! SCNMaterial
        m.emission.contents = on ? UIColor(hex: 0xFFD9A0) : UIColor.black
        m.emission.intensity = on ? 0.55 : 0
        return m
    }

    /// Translucent overlay (footprints, zones, the door swing).
    static func overlay(_ c: UIColor, alpha: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = c.withAlphaComponent(alpha)
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        m.isDoubleSided = true
        return m
    }
}

enum Hue {
    static let sage = UIColor(hex: 0x7E9A83)
    static let terracotta = UIColor(hex: 0xC27C62)
    static let oak = UIColor(hex: 0xA97B50)
    static let ink = UIColor(hex: 0x2F2B27)
    static let paper = UIColor(hex: 0xFBF8F4)
}
