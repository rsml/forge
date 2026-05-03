// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Forge",
            dependencies: ["SwiftTerm"],
            path: "Sources"
        ),
    ]
)
