import Foundation
import PerfectFitCore

/// English by default, Spanish from Settings (studio rule). The app language is chosen in-game, not by the system.
enum Lang: String, Codable, CaseIterable { case en, es }

struct Strings {
    let lang: Lang
    private func t(_ en: String, _ es: String) -> String { lang == .es ? es : en }

    // home
    var play: String { t("Play", "Jugar") }
    var levels: String { t("Levels", "Niveles") }
    var settings: String { t("Settings", "Ajustes") }
    var howToPlay: String { t("How to Play", "Cómo jugar") }
    var records: String { t("Records", "Récords") }
    var byStudio: String { "by BluBer Games" }
    var continueLevel: String { t("Continue", "Continuar") }
    func levelN(_ n: Int) -> String { t("Level \(n)", "Nivel \(n)") }

    // game
    var rotate: String { t("Turn", "Girar") }
    var toTray: String { t("Remove", "Quitar") }
    var hint: String { t("Hint", "Pista") }
    var reset: String { t("Reset", "Reiniciar") }
    var done: String { t("Done", "Listo") }
    var paused: String { t("Paused", "Pausa") }
    var resume: String { t("Resume", "Seguir") }
    var restart: String { t("Restart level", "Reiniciar nivel") }
    var quit: String { t("Back to levels", "Volver a niveles") }
    var allPlaced: String { t("Everything is in place", "Todo está en su lugar") }
    func left(_ n: Int) -> String { n == 1 ? t("1 piece to place", "Falta 1 mueble") : t("\(n) pieces to place", "Faltan \(n) muebles") }
    var noHints: String { t("No hints left. Earn one with every new 3-star room.", "No quedan pistas. Ganas una con cada habitación nueva de 3 estrellas.") }
    var hintNone: String { t("Try moving a few pieces first.", "Prueba mover algunos muebles primero.") }

    // victory
    var perfectFit: String { "Perfect Fit" }
    var nextLevel: String { t("Next Level", "Siguiente nivel") }
    var replay: String { t("Replay", "Repetir") }
    var starFit: String { t("Everything fits", "Todo cabe") }
    var starHarmony: String { t("Harmony", "Armonía") }
    var starFlow: String { t("Flow", "Circulación") }
    func harmonyDetail(_ a: Int, _ b: Int) -> String { b == 0 ? t("Nothing to pair", "Nada que combinar") : t("\(a) of \(b) pieces where they like to be", "\(a) de \(b) muebles donde les gusta estar") }
    func flowDetail(_ ok: Bool) -> String { ok ? t("Every bit of floor is reachable", "Se llega a todo el piso") : t("Some floor is cut off from the door", "Hay piso al que no se llega desde la puerta") }
    var finale: String { t("You furnished every room.", "Amueblaste todas las habitaciones.") }
    var hintEarned: String { t("+1 hint", "+1 pista") }

    // settings
    var sound: String { t("Sound", "Sonido") }
    var vibration: String { t("Vibration", "Vibración") }
    var theme: String { t("Theme", "Tema") }
    var auto: String { t("Auto", "Auto") }
    var light: String { t("Light", "Claro") }
    var dark: String { t("Dark", "Oscuro") }
    var language: String { t("Language", "Idioma") }
    var resetData: String { t("Erase progress", "Borrar progreso") }
    var resetConfirm: String { t("Erase all stars and progress?", "¿Borrar todas las estrellas y el progreso?") }
    var erase: String { t("Erase", "Borrar") }
    var cancel: String { t("Cancel", "Cancelar") }
    var about: String { t("About", "Acerca de") }
    var version: String { t("Version", "Versión") }
    var website: String { t("Website", "Sitio web") }
    var support: String { t("Support", "Soporte") }
    var close: String { t("Close", "Cerrar") }
    var assets: String { t("3D models and textures: Poly Haven (CC0)", "Modelos 3D y texturas: Poly Haven (CC0)") }

    // records
    var stars: String { t("Stars", "Estrellas") }
    var roomsDone: String { t("Rooms furnished", "Habitaciones amuebladas") }
    var perfectRooms: String { t("3-star rooms", "Habitaciones de 3 estrellas") }
    var hintsLeft: String { t("Hints", "Pistas") }

    // pieces
    func piece(_ k: FurnitureKind) -> String { lang == .es ? k.name.es : k.name.en }

    /// What a piece needs, shown when it's selected.
    func needs(_ k: FurnitureKind, rules: [Rule]) -> String {
        var parts: [String] = []
        if k.wallBack { parts.append(t("back to a wall", "de espaldas a una pared")) }
        if rules.contains(.clearance) && !k.zones.isEmpty {
            switch k.id {
            case "bed_single", "bed_double": parts.append(t("one free side", "un lado libre"))
            case "chair": parts.append(t("room behind to pull it out", "espacio detrás para sacarla"))
            case "desk": parts.append(t("room in front for a chair", "espacio enfrente para una silla"))
            case "sofa", "armchair": parts.append(t("room in front to sit", "espacio enfrente para sentarse"))
            default: parts.append(t("room in front to open", "espacio enfrente para abrir"))
            }
        }
        if rules.contains(.windows) {
            if k.tall { parts.append(t("not in front of a window", "no frente a una ventana")) }
            if k.needsWindow { parts.append(t("by a window", "junto a una ventana")) }
        }
        return parts.joined(separator: " · ")
    }

    /// The little preference behind the Harmony star.
    func likes(_ p: Preference) -> String {
        switch p {
        case .nextToBedHead: return t("Likes: beside the head of a bed", "Le gusta: junto a la cabecera")
        case .bothSidesFree: return t("Likes: both sides free", "Le gusta: los dos lados libres")
        case .atDesk: return t("Likes: facing the desk", "Le gusta: frente al escritorio")
        case .inFrontOfSeat: return t("Likes: in front of a seat", "Le gusta: frente a un asiento")
        case .nextToSeat: return t("Likes: beside a seat, desk or bed", "Le gusta: junto a un asiento, escritorio o cama")
        case .lightOrCorner: return t("Likes: window light, or a corner", "Le gusta: la luz de la ventana, o una esquina")
        case .underBedOrSeat: return t("Likes: under a bed or before a seat", "Le gusta: bajo la cama o frente a un asiento")
        case .nearWindow: return t("Likes: daylight", "Le gusta: la luz del día")
        }
    }

    /// One calm sentence for the first problem.
    func issue(_ i: Issue, _ kinds: [FurnitureKind]) -> String {
        func n(_ p: Int) -> String { piece(kinds[p]) }
        switch i {
        case .notPlaced(let c): return left(c)
        case .outsideRoom(let p): return t("The \(n(p).lowercased()) doesn't fit there.", "\(n(p)): no cabe ahí.")
        case .overlaps(let p): return t("The \(n(p).lowercased()) overlaps something.", "\(n(p)): se encima con otro mueble.")
        case .needsWall(let p): return t("The \(n(p).lowercased()) needs its back to a wall.", "\(n(p)): necesita la espalda contra una pared.")
        case .blocksDoor(let p): return t("The \(n(p).lowercased()) is in the door's way.", "\(n(p)): estorba a la puerta.")
        case .zoneBlocked(let p):
            switch kinds[p].id {
            case "bed_single", "bed_double": return t("The bed needs one free side to get in.", "La cama necesita un lado libre para subirse.")
            case "chair": return t("The chair needs room behind it.", "La silla necesita espacio detrás.")
            case "sofa", "armchair": return t("The \(n(p).lowercased()) needs room in front to sit.", "\(n(p)): necesita espacio enfrente para sentarse.")
            case "desk": return t("The desk needs room in front for a chair.", "El escritorio necesita espacio enfrente para una silla.")
            default: return t("The \(n(p).lowercased()) needs room in front to open.", "\(n(p)): necesita espacio enfrente para abrir.")
            }
        case .unreachable(let p): return t("You can't walk to the \(n(p).lowercased()) from the door.", "No se puede llegar a: \(n(p).lowercased()) desde la puerta.")
        case .blocksWindow(let p): return t("The \(n(p).lowercased()) is too tall for a window.", "\(n(p)): es muy alto para ir frente a una ventana.")
        case .needsWindow(let p): return t("The \(n(p).lowercased()) wants to be by a window.", "\(n(p)): quiere estar junto a una ventana.")
        }
    }

    // how to play
    var howSteps: [(String, String)] {
        [
            (t("Drag a piece from the tray into the room.", "Arrastra un mueble de la bandeja a la habitación."), "hand.draw"),
            (t("Tap a piece to select it. Turn it, move it, or send it back to the tray.", "Toca un mueble para elegirlo. Gíralo, muévelo o regrésalo a la bandeja."), "arrow.clockwise"),
            (t("Every room has rules: keep the door clear, give each piece the space it needs, reach everything from the door.", "Cada habitación tiene reglas: deja libre la puerta, da a cada mueble su espacio y llega a todo desde la puerta."), "door.left.hand.open"),
            (t("One star when everything fits. One for Harmony: each piece where it likes to be. One for Flow: no floor cut off from the door.", "Una estrella si todo cabe. Una por Armonía: cada mueble donde le gusta estar. Una por Circulación: ningún pedazo de piso aislado de la puerta."), "star"),
            (t("Pinch to zoom. Turn the room with the camera button.", "Pellizca para acercar. Gira la habitación con el botón de cámara."), "rotate.3d"),
        ]
    }
}
