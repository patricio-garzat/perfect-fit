import XCTest
@testable import PerfectFitCore

/// Every shipped level must load, be well formed, have a valid layout and a 3-star layout.
/// Run with:  swift test -c release   (from Packages/PerfectFitCore)
final class LevelTests: XCTestCase {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("../../PerfectFit/Resources/Levels").standardized

    func levels() throws -> [Level] {
        let files = try FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map(Level.load)
    }

    func testTenLevelsInOrder() throws {
        let ls = try levels()
        XCTAssertEqual(ls.map(\.id), Array(1...10))
    }

    func testLevelData() throws {
        for l in try levels() { XCTAssertEqual(l.dataProblems(), [], "level \(l.id)") }
    }

    func testEveryLevelIsSolvableWithThreeStars() throws {
        for l in try levels() {
            let s = Solver(level: l)
            guard let any = s.find(stars: 1, deadline: Date().addingTimeInterval(30)) else { XCTFail("level \(l.id) has no solution"); continue }
            var layout = Layout(level: l)
            layout.placements = any
            XCTAssertTrue(layout.evaluate().valid, "level \(l.id)")
            guard let best = s.find(stars: 3, deadline: Date().addingTimeInterval(60)) else { XCTFail("level \(l.id) has no 3-star layout"); continue }
            layout.placements = best
            let e = layout.evaluate()
            XCTAssertEqual(e.stars, 3, "level \(l.id)\n\(s.draw(best))")
        }
    }

    /// Hints solve around what the player already placed.
    func testHintKeepsPlacedPieces() throws {
        let l = try levels()[1]
        let s = Solver(level: l)
        let sol = try XCTUnwrap(s.find(stars: 1, deadline: Date().addingTimeInterval(10)))
        let fixed = [0: sol[0]]
        let again = try XCTUnwrap(s.find(stars: 1, fixed: fixed, deadline: Date().addingTimeInterval(10)))
        XCTAssertEqual(Set(Catalog.kind(l.pieceKinds[0]).cells(at: again[0])), Set(Catalog.kind(l.pieceKinds[0]).cells(at: sol[0])))
    }
}

final class RuleTests: XCTestCase {
    func level(_ json: String) throws -> Level { try JSONDecoder().decode(Level.self, from: Data(json.utf8)) }

    let base = """
    { "id": 99, "name": { "en": "t", "es": "t" }, "shape": ["######", "######", "######", "######", "######", "######"],
      "doors": [{ "cell": [3, 5], "side": "S", "width": 2 }], "windows": [{ "cell": [0, 0], "side": "N", "width": 2 }],
      "pieces": ["bed_single", "wardrobe"], "rules": ["clearance", "access", "windows"] }
    """

    func testRotationMapsFrontAndFootprint() {
        let bed = Catalog.kind("bed_single")
        // turned once the bed lies along x, its head (v=0) at the left
        let p = Placement(origin: Cell(0, 0), rotation: Rotation(1))
        XCTAssertEqual(Set(bed.cells(at: p)), Set((0..<4).flatMap { x in (0..<2).map { Cell(x, $0) } }))
        XCTAssertEqual(Set(bed.headCells(at: p)), [Cell(0, 0), Cell(0, 1)])
        XCTAssertEqual(Rotation(1).front, Cell(1, 0))
    }

    func testValidAndIssues() throws {
        var l = Layout(level: try level(base))
        l.placements[0] = Placement(origin: Cell(2, 0), rotation: Rotation(0))   // head on the north wall
        l.placements[1] = Placement(origin: Cell(0, 4), rotation: Rotation(1))   // back on the west wall
        XCTAssertTrue(l.evaluate().valid, "\(l.evaluate().issues)")

        // wardrobe away from the wall
        l.placements[1] = Placement(origin: Cell(1, 4), rotation: Rotation(1))
        XCTAssertTrue(l.evaluate().issues.contains(.needsWall(1)))
        // wardrobe in front of the window
        l.placements[1] = Placement(origin: Cell(0, 0), rotation: Rotation(0))
        XCTAssertTrue(l.evaluate().issues.contains(.blocksWindow(1)))
        // bed in the door swing
        l.placements[1] = Placement(origin: Cell(0, 4), rotation: Rotation(1))
        l.placements[0] = Placement(origin: Cell(3, 2), rotation: Rotation(2))
        XCTAssertTrue(l.evaluate().issues.contains(.blocksDoor(0)))
    }

    func testCanPlaceRejectsOverlap() throws {
        var l = Layout(level: try level(base))
        l.placements[0] = Placement(origin: Cell(2, 0), rotation: Rotation(0))
        XCTAssertFalse(l.canPlace(1, at: Placement(origin: Cell(2, 1), rotation: Rotation(0))))
        XCTAssertFalse(l.canPlace(1, at: Placement(origin: Cell(5, 0), rotation: Rotation(0))))   // out of the room
        XCTAssertTrue(l.canPlace(1, at: Placement(origin: Cell(4, 0), rotation: Rotation(0))))
    }
}
