// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Return",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CReturnAudio",
            path: "NativeAudio",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Return",
            dependencies: ["CReturnAudio"],
            path: "Sources"
        ),
        .testTarget(
            name: "CReturnAudioTests",
            dependencies: ["CReturnAudio"],
            path: "Tests/CReturnAudioTests"
        ),
    ]
)
