// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AgentMeter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentMeter",
            path: "Sources/AgentMeter"
        ),
        .testTarget(
            name: "AgentMeterTests",
            dependencies: ["AgentMeter"],
            path: "Tests/AgentMeterTests"
        ),
    ]
)
