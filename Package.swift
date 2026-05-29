// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPet",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AgentPet",
            path: "Sources/AgentPet"
        )
    ]
)
