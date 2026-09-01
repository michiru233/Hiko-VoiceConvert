// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceConvertCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "VoiceConvertCore", targets: ["VoiceConvertCore"]),
    ],
    targets: [
        .target(name: "VoiceConvertCore", path: "Sources/VoiceConvertCore"),
        .testTarget(name: "VoiceConvertCoreTests", dependencies: ["VoiceConvertCore"], path: "Tests/VoiceConvertCoreTests"),
    ]
)
