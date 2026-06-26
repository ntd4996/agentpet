// swift-tools-version: 6.0
import PackageDescription

var dependencies: [Package.Dependency] = []
var products: [Product] = [
    .library(name: "AgentPetCore", targets: ["AgentPetCore"]),
]
var targets: [Target] = [
    .target(
        name: "AgentPetCore",
        path: "Sources/AgentPetCore"
    ),
    .testTarget(
        name: "AgentPetCoreTests",
        dependencies: ["AgentPetCore"],
        path: "Tests/AgentPetCoreTests"
    ),
]

#if os(macOS)
dependencies.append(
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
)

products.append(.executable(name: "agentpet", targets: ["agentpet"]))

targets.append(
    .executableTarget(
        name: "agentpet",
        dependencies: ["AgentPetCore", .product(name: "Sparkle", package: "Sparkle")],
        path: "Sources/App"
    )
)

targets.append(
    .testTarget(
        name: "AgentPetAppTests",
        dependencies: ["agentpet"],
        path: "Tests/AgentPetAppTests"
    )
)
#endif

let package = Package(
    name: "AgentPet",
    products: products,
    dependencies: dependencies,
    targets: targets
)
