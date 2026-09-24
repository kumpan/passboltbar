// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PassboltBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PassboltBar"),
        .testTarget(name: "PassboltBarTests", dependencies: ["PassboltBar"]),
    ],
    swiftLanguageModes: [.v5]
)
