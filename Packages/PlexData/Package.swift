// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlexData",
    platforms: [.macOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "PlexModels", targets: ["PlexModels"]),
        .library(name: "PlexMockData", targets: ["PlexMockData"]),
    ],
    targets: [
        .target(name: "PlexModels"),
        .target(name: "PlexMockData", dependencies: ["PlexModels"]),
        .testTarget(name: "PlexModelsTests", dependencies: ["PlexModels"]),
        .testTarget(name: "PlexMockDataTests", dependencies: ["PlexMockData"]),
    ]
)
