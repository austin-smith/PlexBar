// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PlexClient",
    platforms: [.macOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "PlexClientKit", targets: ["PlexClientKit"]),
        .library(name: "PlexTopShelf", targets: ["PlexTopShelf"]),
    ],
    dependencies: [.package(path: "../PlexData")],
    targets: [
        .target(name: "PlexClientKit", dependencies: [.product(name: "PlexModels", package: "PlexData")]),
        .target(name: "PlexTopShelf"),
    ]
)
