import Foundation
import Observation
import PerfectFitCore

/// One level being played: the layout, its evaluation and every player action.
/// The 3D scene (SceneController) reads from here and calls back with placements.
@Observable
final class GameSession {
    let level: Level
    private(set) var layout: Layout
    private(set) var eval: Evaluation
    var selected: Int? { didSet { if oldValue != selected { onChange?(.selection) } } }
    /// Rotation each piece keeps while in the tray (so a turned piece stays turned).
    private(set) var trayRotation: [Rotation]
    private(set) var hintBusy = false
    var toast: String?

    enum Change { case all, piece(Int), selection, hint(Int) }
    @ObservationIgnored var onChange: ((Change) -> Void)?

    init(level: Level) {
        self.level = level
        let l = Layout(level: level)
        layout = l
        eval = l.evaluate()
        trayRotation = Array(repeating: Rotation(0), count: l.kinds.count)
    }

    var kinds: [FurnitureKind] { layout.kinds }
    var trayPieces: [Int] { layout.placements.indices.filter { layout.placements[$0] == nil } }
    var isComplete: Bool { eval.valid }
    var room: Room { layout.room }

    func placement(_ i: Int) -> Placement? { layout.placements[i] }
    func rotation(_ i: Int) -> Rotation { layout.placements[i]?.rotation ?? trayRotation[i] }
    func canPlace(_ i: Int, _ p: Placement) -> Bool { layout.canPlace(i, at: p) }

    // MARK: - actions

    /// Drops a piece. Returns false (and leaves things as they were) when it can't go there.
    @discardableResult
    func place(_ i: Int, _ p: Placement) -> Bool {
        guard layout.canPlace(i, at: p) else { feedbackInvalid(); return false }
        let wasValid = eval.valid
        layout.placements[i] = p
        trayRotation[i] = p.rotation
        reevaluate(wasValid: wasValid)
        let k = kinds[i]
        Sound.shared.play(k.w * k.d >= 6 || k.tall ? .placeHeavy : .place, volume: k.layer == .floor ? 0.6 : 1)
        Haptics.shared.play(.place)
        onChange?(.piece(i))
        return true
    }

    func remove(_ i: Int) {
        guard layout.placements[i] != nil else { return }
        let wasValid = eval.valid
        trayRotation[i] = layout.placements[i]!.rotation
        layout.placements[i] = nil
        if selected == i { selected = nil }
        reevaluate(wasValid: wasValid)
        Sound.shared.play(.toTray, volume: 0.8)
        Haptics.shared.play(.select)
        onChange?(.piece(i))
    }

    /// Quarter turn of the selected piece, in place. Nudges it a cell if it would otherwise not fit.
    func rotateSelected() {
        guard let i = selected else { return }
        guard let p = layout.placements[i] else {
            trayRotation[i] = trayRotation[i].next
            Sound.shared.play(.rotate); Haptics.shared.play(.rotate)
            onChange?(.piece(i))
            return
        }
        let k = kinds[i]
        let r = p.rotation.next
        let (w0, h0) = k.rotatedSize(p.rotation), (w1, h1) = k.rotatedSize(r)
        // keep the center where it was
        let cx = Double(p.origin.x) + Double(w0) / 2, cy = Double(p.origin.y) + Double(h0) / 2
        let base = Cell(Int((cx - Double(w1) / 2).rounded(.down)), Int((cy - Double(h1) / 2).rounded(.down)))
        let tries = [Cell(0, 0), Cell(1, 0), Cell(0, 1), Cell(-1, 0), Cell(0, -1), Cell(1, 1), Cell(-1, -1), Cell(1, -1), Cell(-1, 1)]
        for d in tries {
            let q = Placement(origin: base + d, rotation: r)
            if layout.canPlace(i, at: q) {
                let wasValid = eval.valid
                layout.placements[i] = q
                trayRotation[i] = r
                reevaluate(wasValid: wasValid)
                Sound.shared.play(.rotate); Haptics.shared.play(.rotate)
                onChange?(.piece(i))
                return
            }
        }
        feedbackInvalid()
    }

    /// Silent: used by the home screen's showcase room.
    func setLayout(_ placements: [Placement]) {
        for (i, p) in placements.enumerated() { layout.placements[i] = p }
        eval = layout.evaluate()
    }

    func reset() {
        layout = Layout(level: level)
        trayRotation = Array(repeating: Rotation(0), count: kinds.count)
        selected = nil
        eval = layout.evaluate()
        onChange?(.all)
    }

    func feedbackInvalid() {
        Sound.shared.play(.invalid)
        Haptics.shared.play(.error)
    }

    private func reevaluate(wasValid: Bool) {
        eval = layout.evaluate()
        if eval.valid && !wasValid {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Sound.shared.play(.valid)
                Haptics.shared.play(.valid)
            }
        }
    }

    /// The first thing to tell the player, if anything.
    var statusLine: String? { nil }

    // MARK: - hints

    /// Finds a good layout around what's already placed and moves one piece to its spot.
    func hint(completion: @escaping (Bool) -> Void) {
        guard !hintBusy else { return }
        hintBusy = true
        let level = self.level, current = layout, valid = eval.valid
        // pieces placed without problems stay; the rest can move
        var keep: [Int: Placement] = [:]
        let troubled = Set(eval.issues.compactMap(\.piece))
        for (i, p) in current.placements.enumerated() where p != nil && !troubled.contains(i) { keep[i] = p! }
        DispatchQueue.global(qos: .userInitiated).async {
            let solver = Solver(level: level)
            let soon = Date().addingTimeInterval(1.2)
            let target = solver.find(stars: 3, fixed: keep, deadline: soon, nodesPerTry: 20_000)
                ?? solver.find(stars: valid ? 3 : 1, fixed: keep, deadline: Date().addingTimeInterval(0.6), nodesPerTry: 20_000)
                ?? solver.find(stars: 3, deadline: Date().addingTimeInterval(1.5), nodesPerTry: 30_000)
                ?? solver.find(stars: 1, deadline: Date().addingTimeInterval(1.5), nodesPerTry: 30_000)
            DispatchQueue.main.async {
                self.hintBusy = false
                guard let target else { completion(false); return }
                completion(self.apply(hint: target))
            }
        }
    }

    /// Moves one piece toward the target layout (the first one that differs), clearing its spot if needed.
    private func apply(hint target: [Placement]) -> Bool {
        let order = layout.kinds.indices.sorted { a, b in
            // unplaced first, then the big ones
            let ua = layout.placements[a] == nil, ub = layout.placements[b] == nil
            if ua != ub { return ua }
            return kinds[a].w * kinds[a].d > kinds[b].w * kinds[b].d
        }
        for i in order {
            let want = target[i]
            if let p = layout.placements[i], Set(kinds[i].cells(at: p)) == Set(kinds[i].cells(at: want)) { continue }
            let wasValid = eval.valid
            // clear pieces in the way
            let cells = Set(kinds[i].cells(at: want))
            for (j, q) in layout.placements.enumerated() where j != i {
                guard let q, kinds[j].layer == kinds[i].layer else { continue }
                if !cells.isDisjoint(with: kinds[j].cells(at: q)) { layout.placements[j] = nil; onChange?(.piece(j)) }
            }
            layout.placements[i] = want
            trayRotation[i] = want.rotation
            selected = i
            reevaluate(wasValid: wasValid)
            Sound.shared.play(.place)
            Haptics.shared.play(.place)
            onChange?(.hint(i))
            return true
        }
        return false
    }
}
