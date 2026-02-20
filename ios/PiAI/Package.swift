// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "PiAI",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PiAI", targets: ["PiAI"]),
    ],
    targets: [
        .target(name: "PiAI", path: "Sources/PiAI"),
    ]
)
