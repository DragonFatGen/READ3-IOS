// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LegadoCore",
    platforms: [
        .iOS(.v16),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "LegadoCore",
            targets: ["LegadoCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.13.7")
    ],
    targets: [
        .target(
            name: "LegadoCore",
            dependencies: ["SwiftSoup"]
        ),
        .testTarget(
            name: "LegadoCoreTests",
            dependencies: ["LegadoCore"]
        )
    ]
)
