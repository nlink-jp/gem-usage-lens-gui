// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GemUsageLens",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GemUsageLens",
            path: "Sources/GemUsageLens"
        ),
        .testTarget(
            name: "GemUsageLensTests",
            dependencies: ["GemUsageLens"],
            path: "Tests/GemUsageLensTests"
        ),
    ]
)
