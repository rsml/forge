// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        // Shared kernel — domain models, ports, pure logic. No framework deps.
        .target(
            name: "ForgeCore",
            dependencies: [],
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "Forge",
            dependencies: ["SwiftTerm", "ForgeCore"],
            path: "Sources",
            exclude: ["Core"]
        ),
        .testTarget(
            name: "ForgeTests",
            dependencies: ["ForgeCore"],
            path: "Tests/ForgeTests"
        ),
    ]
)
