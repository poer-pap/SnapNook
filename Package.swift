// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SnapNook",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SnapNook", targets: ["SnapNook"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0")
    ],
    targets: [
        .executableTarget(
            name: "SnapNook",
            dependencies: [
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")
            ]
        )
    ]
)
