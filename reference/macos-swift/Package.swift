// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MicFlip",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MicFlip",
            path: "Sources/MicFlip"
        )
    ]
)
