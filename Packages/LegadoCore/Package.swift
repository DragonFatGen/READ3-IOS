// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LegadoCore",
    products: [
        .library(
            name: "LegadoCore",
            targets: ["LegadoCore"]
        )
    ],
    targets: [
        .target(name: "LegadoCore"),
        .testTarget(
            name: "LegadoCoreTests",
            dependencies: ["LegadoCore"]
        )
    ]
)
