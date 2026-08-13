// swift-tools-version:5.9
// SwiftPM manifest used ONLY to run the diagnosis-engine unit tests on macOS
// (`swift test`). This Xcode install cannot run destination-based simulator
// tests ("iOS platform not installed"), and the diagnosis code is pure Swift,
// so testing on the host is both possible and much faster. The app itself is
// still built from project.yml via xcodegen + xcodebuild.
import PackageDescription

let package = Package(
    name: "EngSoundlyCore",
    targets: [
        .target(
            name: "EngSoundlyCore",
            path: ".",
            sources: [
                "Sources/Models/PhonemeMapping.swift",
                "Sources/Diagnosis",
            ]
        ),
        .testTarget(
            name: "EngSoundlyCoreTests",
            dependencies: ["EngSoundlyCore"],
            path: "Tests"
        ),
    ]
)
