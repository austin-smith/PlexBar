// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlexBar",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "PlexBar",
            targets: ["PlexBar"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1")
    ],
    targets: [
        .executableTarget(
            name: "PlexBar",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: [
                "Resources/MockServer"
            ],
            resources: [
                .process("Resources/MenuBarIcon.png"),
                .process("Resources/MenuBarIcon@2x.png")
            ]
        ),
        .testTarget(
            name: "PlexBarTests",
            dependencies: ["PlexBar"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
