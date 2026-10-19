// Level tool: solves every level and prints how many solutions it has, how many reach each star count,
// and a plan of the best one. Use it while designing levels.
//
//   cd Packages/PerfectFitCore && swift run -c release pf-levels ../../PerfectFit/Resources/Levels [ids…]
import Foundation
import PerfectFitCore

setvbuf(stdout, nil, _IOLBF, 0)
let seconds = Double(ProcessInfo.processInfo.environment["PF_SECONDS"] ?? "20") ?? 20

let args = CommandLine.arguments.dropFirst()
let dir = URL(fileURLWithPath: args.first ?? "../../PerfectFit/Resources/Levels")
let only = Set(args.dropFirst().compactMap(Int.init))
let files = (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
    .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

var failed = false
for f in files {
    let level = try Level.load(f)
    if !only.isEmpty && !only.contains(level.id) { continue }
    for problem in level.dataProblems() { print("   ✗ level \(level.id): \(problem)"); failed = true }
    let t0 = Date()
    let s = Solver(level: level)
    var r = s.solve(deadline: Date().addingTimeInterval(seconds))
    let dt = Date().timeIntervalSince(t0)
    if r.bestStars < 3 {
        // counting was cut short: look for a 3-star layout directly
        let t0 = Date()
        if let b = s.find(stars: 3, deadline: Date().addingTimeInterval(seconds * 3)) { r.best = b; r.bestStars = 3 }
        else if r.bestStars == 0, let b = s.find(stars: 1, deadline: Date().addingTimeInterval(seconds)) { r.best = b; r.bestStars = 1 }
        print("   (3★ search \(String(format: "%.2fs", Date().timeIntervalSince(t0))))")
    }
    print("── \(level.id). \(level.name.en)  [\(level.rules.map(\.rawValue).joined(separator: ", "))]")
    print("   pieces: \(level.pieceKinds.joined(separator: ", "))")
    print("   solutions: \(r.solutions)\(r.complete ? "" : "+ (stopped)")   1★ \(r.byStars[1])  2★ \(r.byStars[2])  3★ \(r.byStars[3])   (harmony \(r.withHarmony), flow \(r.withFlow))   nodes \(r.nodes)   \(String(format: "%.2fs", dt))")
    if let b = r.best { print(s.draw(b).split(separator: "\n").map { "   " + $0 }.joined(separator: "\n")) }
    if r.best == nil || r.bestStars < 3 { print("   ✗ needs a fix"); failed = true }
}
exit(failed ? 1 : 0)
