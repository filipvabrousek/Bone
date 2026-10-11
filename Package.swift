// swift-tools-version: 6.2
//
// Bone as a Swift package: the library in library/ (a mirror of Bone-27/Bone-27/library).
// Every file is wrapped in #if DEBUG, so Release builds of an app that depends on Bone
// contain none of it. Tests: swift test (macOS), or Bone-27/Tests/run.sh for every platform.

import PackageDescription

let package = Package(
    name: "Bone",
    platforms: [.iOS("27.0"), .macOS("26.5"), .watchOS("27.0"), .visionOS("27.0")],
    products: [
        .library(name: "Bone", targets: ["Bone"]),
    ],
    targets: [
        .target(
            name: "Bone",
            path: "library",
            exclude: ["readme.md", "CHANGELOG.md"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .testTarget(
            name: "BoneTests",
            dependencies: ["Bone"],
            path: "Bone-27/Tests/BoneTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
