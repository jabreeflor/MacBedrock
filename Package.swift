// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacBedrock",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacBedrock", targets: ["MacBedrock"])],
    targets: [
        .target(name: "MacBedrockCore"),
        .executableTarget(name: "MacBedrock", dependencies: ["MacBedrockCore"]),
        .testTarget(name: "MacBedrockCoreTests", dependencies: ["MacBedrockCore"])
    ]
)
