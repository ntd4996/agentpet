// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentPet",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "AgentPetCore",
            path: "Sources/AgentPetCore"
        ),
        .executableTarget(
            name: "agentpet",
            dependencies: ["AgentPetCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AgentPetCoreTests",
            dependencies: ["AgentPetCore"],
            path: "Tests/AgentPetCoreTests"
        ),
        .testTarget(
            name: "AgentPetAppTests",
            dependencies: ["agentpet"],
            path: "Tests/AgentPetAppTests"
        ),
    ]
)
