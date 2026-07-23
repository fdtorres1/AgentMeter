// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AgentMeter",
    defaultLocalization: "en",
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
            path: "Sources/AgentMeter",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AgentMeterTests",
            dependencies: ["AgentMeter"],
            path: "Tests/AgentMeterTests"
        ),
    ]
)
