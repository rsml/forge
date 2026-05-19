// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        // Shared kernel — domain models, ports, pure logic. No framework deps.
        .target(
            name: "ForgeCore",
            dependencies: [],
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "Forge",
            dependencies: ["ForgeCore", "GhosttyKit"],
            path: "Sources",
            exclude: ["Core", "Daemon"],
            swiftSettings: [
                .define("GHOSTTY_HAS_IO_READ_CB"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Carbon"),
            ]
        ),
        .executableTarget(
            name: "forged",
            dependencies: ["ForgeCore"],
            path: "Sources/Daemon"
        ),
        .binaryTarget(
            name: "GhosttyKit",
            path: "GhosttyKit.xcframework"
        ),
        .testTarget(
            name: "ForgeTests",
            dependencies: ["ForgeCore"],
            path: "Tests/ForgeTests"
        ),
    ]
)
