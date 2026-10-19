// swift-tools-version:5.9
// Perfect Fit · game logic with no UIKit/SceneKit: grid, levels, rules, stars and the solver.
// The app links it; `swift test` and `swift run pf-levels` run it on the Mac.
import PackageDescription

let package = Package(
    name: "PerfectFitCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PerfectFitCore", targets: ["PerfectFitCore"])],
    targets: [
        .target(name: "PerfectFitCore"),
        .executableTarget(name: "pf-levels", dependencies: ["PerfectFitCore"]),
        .testTarget(name: "PerfectFitCoreTests", dependencies: ["PerfectFitCore"]),
    ]
)
