// swift-tools-version: 6.0
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let lameArchive = packageRoot.appendingPathComponent("../ThirdParty/lib/libmp3lame.a").standardizedFileURL.path
let mpg123Archive = packageRoot.appendingPathComponent("../ThirdParty/lib/libmpg123.a").standardizedFileURL.path

let package = Package(
    name: "VoiceConvertCLI",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "voiceconvert", targets: ["voiceconvert"]),
        .library(name: "VoiceConvertCLIKit", targets: ["VoiceConvertCLIKit"]),
    ],
    dependencies: [
        .package(path: "../VoiceConvertCore")
    ],
    targets: [
        .target(
            name: "VoiceConvertLAME",
            path: "Sources/VoiceConvertLAME",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ]
        ),
        .target(
            name: "VoiceConvertAudioBackend",
            dependencies: ["VoiceConvertLAME"],
            path: "Sources/VoiceConvertAudioBackend",
            linkerSettings: [
                .unsafeFlags([
                    "\(lameArchive)",
                    "\(mpg123Archive)"
                ]),
                .linkedFramework("AVFoundation", .when(platforms: [.macOS]))
            ]
        ),
        .target(
            name: "VoiceConvertCLIKit",
            dependencies: [
                .product(name: "VoiceConvertCore", package: "VoiceConvertCore"),
                "VoiceConvertAudioBackend"
            ],
            path: "Sources/VoiceConvertCLIKit"
        ),
        .executableTarget(
            name: "voiceconvert",
            dependencies: ["VoiceConvertCLIKit"],
            path: "Sources/voiceconvert"
        ),
        .testTarget(
            name: "VoiceConvertCLITests",
            dependencies: [
                .product(name: "VoiceConvertCore", package: "VoiceConvertCore"),
                "VoiceConvertCLIKit",
                "VoiceConvertAudioBackend"
            ],
            path: "Tests/VoiceConvertCLITests"
        ),
    ]
)
