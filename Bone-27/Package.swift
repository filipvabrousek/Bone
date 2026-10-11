// swift-tools-version: 6.2
//
// Bone as a Swift package. The library is the same folder the demo app compiles
// (Bone-27/library); every file is wrapped in #if DEBUG, so Release builds of an
// app that depends on Bone contain none of it.
//
//   swift test                                   # macOS
//   xcodebuild test -scheme Bone -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
//   Tests/run.sh                                 # everything: tests + every platform, Debug and Release

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
            path: "Bone-27/library",
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
            path: "Tests/BoneTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
