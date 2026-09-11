// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Sendpoint",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "SendpointDomain",
            targets: ["SendpointDomain"]
        ),
        .executable(
            name: "Sendpoint",
            targets: ["Sendpoint"]
        ),
    ],
    dependencies: [
        // Hex uses FluidAudio for its fast, local Parakeet transcription.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5"),
    ],
    targets: [
        .target(
            name: "SendpointDomain",
            path: "Sources/SendpointDomain",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .executableTarget(
            name: "Sendpoint",
            dependencies: ["SendpointDomain", "FluidAudio"],
            path: "Sources/Sendpoint",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .testTarget(
            name: "SendpointDomainTests",
            dependencies: ["SendpointDomain"],
            path: "Tests/SendpointDomainTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .testTarget(
            name: "SendpointTests",
            dependencies: ["Sendpoint", "SendpointDomain"],
            path: "Tests/SendpointTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ]
)
