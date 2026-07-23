// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AgentMeter",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentMeter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/AgentMeter"
        ),
        .testTarget(
            name: "AgentMeterTests",
            dependencies: ["AgentMeter"],
            path: "Tests/AgentMeterTests"
        ),
    ]
)
