// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RandomActionLauncher",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "RandomActionLauncher",
            targets: ["RandomActionLauncher"]
        )
    ],
    targets: [
        .executableTarget(
            name: "RandomActionLauncher"
        )
    ]
)
