// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HanabiKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v12),
    ],
    products: [
        .library(name: "HanabiKit", targets: ["HanabiKit"]),
    ],
    targets: [
        .target(name: "HanabiKit"),
        .testTarget(name: "HanabiKitTests", dependencies: ["HanabiKit"]),
    ]
)
