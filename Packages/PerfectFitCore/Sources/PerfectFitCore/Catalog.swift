// Every piece of furniture the game knows. Sizes are in cells (50 cm). The front of a piece is local +v.

public enum Layer: String, Codable, Sendable {
    case solid  // blocks the floor
    case floor  // rugs: other pieces may stand on them, but rugs never overlap rugs
}

/// Space a piece needs to be used (open a door, pull a chair, get into bed).
public struct UseZone: Hashable, Sendable {
    public var rect: LocalRect
    /// Piece kinds that may stand inside this zone anyway (a chair tucked at a desk, a coffee table before a sofa).
    public var allows: Set<String> = []
}

/// Little design preferences. All of them met = the Harmony star.
public enum Preference: String, Codable, Sendable {
    case nextToBedHead     // nightstand beside the head of a bed
    case bothSidesFree     // double bed reachable from both sides
    case atDesk            // chair facing a desk or table
    case inFrontOfSeat     // coffee table in front of a sofa or armchair
    case nextToSeat        // floor lamp beside a sofa, armchair or desk
    case lightOrCorner     // plant in window light (or in a corner if the room has no window)
    case underBedOrSeat    // rug under a bed or in front of a seat
    case nearWindow        // desk by a window (when the room has one)
}

public struct FurnitureKind: Sendable, Identifiable {
    public let id: String
    public let w: Int, d: Int
    public var layer: Layer = .solid
    /// Back must touch a wall (beds, wardrobes, dressers…).
    public var wallBack = false
    /// Too tall to stand in front of a window.
    public var tall = false
    /// Use zones. `anyZone` = at least one is enough (a bed needs one free side), otherwise all of them.
    public var zones: [UseZone] = []
    public var anyZone = false
    /// Must touch a window (only enforced by levels with the "windows" rule).
    public var needsWindow = false
    public var preference: Preference? = nil
    public var name: (en: String, es: String)

    public var isSeat: Bool { ["sofa", "armchair"].contains(id) }
    public var isBed: Bool { id.hasPrefix("bed") }
}

public enum Catalog {
    static func front(_ w: Int, _ d: Int, allows: Set<String> = []) -> UseZone { UseZone(rect: LocalRect(u: 0, v: d, w: w, h: 1), allows: allows) }

    public static let kinds: [String: FurnitureKind] = {
        let list: [FurnitureKind] = [
            FurnitureKind(id: "bed_single", w: 2, d: 4, wallBack: true,
                          zones: [UseZone(rect: LocalRect(u: -1, v: 1, w: 1, h: 3)), UseZone(rect: LocalRect(u: 2, v: 1, w: 1, h: 3))],
                          anyZone: true, name: ("Single bed", "Cama individual")),
            FurnitureKind(id: "bed_double", w: 3, d: 4, wallBack: true,
                          zones: [UseZone(rect: LocalRect(u: -1, v: 1, w: 1, h: 3)), UseZone(rect: LocalRect(u: 3, v: 1, w: 1, h: 3))],
                          anyZone: true, preference: .bothSidesFree, name: ("Double bed", "Cama matrimonial")),
            FurnitureKind(id: "nightstand", w: 1, d: 1, wallBack: true, preference: .nextToBedHead, name: ("Nightstand", "Buró")),
            FurnitureKind(id: "wardrobe", w: 2, d: 1, wallBack: true, tall: true, zones: [front(2, 1)], name: ("Wardrobe", "Armario")),
            FurnitureKind(id: "dresser", w: 2, d: 1, wallBack: true, zones: [front(2, 1)], name: ("Dresser", "Cómoda")),
            FurnitureKind(id: "bookcase", w: 2, d: 1, wallBack: true, tall: true, zones: [front(2, 1)], name: ("Bookcase", "Librero")),
            FurnitureKind(id: "desk", w: 2, d: 1, wallBack: true, zones: [front(2, 1, allows: ["chair"])],
                          needsWindow: true, preference: .nearWindow, name: ("Desk", "Escritorio")),
            FurnitureKind(id: "chair", w: 1, d: 1, zones: [UseZone(rect: LocalRect(u: 0, v: -1, w: 1, h: 1))],
                          preference: .atDesk, name: ("Chair", "Silla")),
            FurnitureKind(id: "armchair", w: 2, d: 2, zones: [front(2, 2, allows: ["coffee_table", "round_table"])], name: ("Armchair", "Sillón")),
            FurnitureKind(id: "sofa", w: 4, d: 2, wallBack: true, zones: [front(4, 2, allows: ["coffee_table", "round_table"])], name: ("Sofa", "Sofá")),
            FurnitureKind(id: "coffee_table", w: 2, d: 1, preference: .inFrontOfSeat, name: ("Coffee table", "Mesa de centro")),
            FurnitureKind(id: "round_table", w: 2, d: 2, preference: .inFrontOfSeat, name: ("Round table", "Mesa redonda")),
            FurnitureKind(id: "floor_lamp", w: 1, d: 1, preference: .nextToSeat, name: ("Floor lamp", "Lámpara de pie")),
            FurnitureKind(id: "plant", w: 1, d: 1, preference: .lightOrCorner, name: ("Plant", "Planta")),
            FurnitureKind(id: "rug", w: 4, d: 3, layer: .floor, preference: .underBedOrSeat, name: ("Rug", "Alfombra")),
            FurnitureKind(id: "rug_small", w: 3, d: 2, layer: .floor, preference: .underBedOrSeat, name: ("Small rug", "Tapete")),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    public static func kind(_ id: String) -> FurnitureKind {
        guard let k = kinds[id] else { fatalError("Unknown furniture kind \(id)") }
        return k
    }
}
