// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WorkRhythm",
    platforms: [.macOS(.v14)],
    products: [.library(name: "WorkRhythmCore", targets: ["WorkRhythmCore"])],
    targets: [
        .target(name: "WorkRhythmCore", path: "Sources/Core"),
        .testTarget(name: "WorkRhythmCoreTests", dependencies: ["WorkRhythmCore"], path: "Tests")
    ]
)
