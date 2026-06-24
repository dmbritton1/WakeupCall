// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChallengeCore",
    // Pure logic — builds on macOS so `swift test` runs on the Mac with no
    // simulator or device. The app target consumes it on iOS 26.
    platforms: [
        .iOS(.v26),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ChallengeCore", targets: ["ChallengeCore"]),
    ],
    targets: [
        .target(
            name: "ChallengeCore",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "ChallengeCoreTests",
            dependencies: ["ChallengeCore"],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
