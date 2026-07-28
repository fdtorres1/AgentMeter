// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AgentMeter",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        // Named case-distinct from the AgentMeter app binary: on the default
        // case-insensitive APFS, products "AgentMeter" and "agentmeter" would
        // clobber each other in .build. bundle.sh installs it into the app
        // bundle as Contents/Helpers/agentmeter.
        .executable(name: "agentmeter-cli", targets: ["agentmeter-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "AgentMeterStatusKit",
            path: "Sources/AgentMeterStatusKit"
        ),
        .executableTarget(
            name: "AgentMeter",
            dependencies: [
                "AgentMeterStatusKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/AgentMeter",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "agentmeter-cli",
            dependencies: ["AgentMeterStatusKit"],
            path: "Sources/agentmeter-cli"
        ),
        .testTarget(
            name: "AgentMeterStatusKitTests",
            dependencies: ["AgentMeterStatusKit"],
            path: "Tests/AgentMeterStatusKitTests",
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "AgentMeterTests",
            dependencies: ["AgentMeter", "AgentMeterStatusKit"],
            path: "Tests/AgentMeterTests"
        ),
    ]
)
