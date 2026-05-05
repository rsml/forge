// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        // Pure domain types — no SwiftUI/AppKit deps, fully testable.
        .target(
            name: "ForgeDomain",
            dependencies: [],
            path: "Sources/Domain"
        ),
        .executableTarget(
            name: "Forge",
            dependencies: ["SwiftTerm", "ForgeDomain"],
            path: "Sources",
            exclude: ["Domain"]
        ),
        .testTarget(
            name: "ForgeTests",
            dependencies: ["ForgeDomain"],
            path: "Tests/ForgeTests"
        ),
    ]
)
