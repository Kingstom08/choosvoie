// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChoosVoieCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ChoosVoieCore", targets: ["ChoosVoieCore"]),
    ],
    targets: [
        .target(
            name: "ChoosVoieCore",
            path: "Sources/ChoosVoieCore"
        ),
        .testTarget(
            name: "ChoosVoieCoreTests",
            dependencies: ["ChoosVoieCore"],
            path: "Tests/ChoosVoieCoreTests"
        ),
    ]
)
