// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlexBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PlexBar",
            targets: ["PlexBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PlexBar"
        ),
        .testTarget(
            name: "PlexBarTests",
            dependencies: ["PlexBar"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
