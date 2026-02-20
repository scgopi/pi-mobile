// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiSession",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PiSession", targets: ["PiSession"]),
    ],
    dependencies: [
        .package(path: "../PiAI"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
    ],
    targets: [
        .target(
            name: "PiSession",
            dependencies: [
                "PiAI",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/PiSession"
        ),
    ]
)
