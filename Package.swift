// swift-tools-version:6.2
import PackageDescription

// Flags any function or expression that is slow to type-check.
let typeCheckBudget: [SwiftSetting] = [
    .unsafeFlags([
        "-Xfrontend", "-warn-long-function-bodies=100",
        "-Xfrontend", "-warn-long-expression-type-checking=100",
    ], .when(configuration: .debug)),
]

let package = Package(
    name: "Sendpoint",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "Core", swiftSettings: typeCheckBudget),
        .executableTarget(
            name: "Sendpoint",
            dependencies: ["Core"],
            path: "Sources/App",
            swiftSettings: typeCheckBudget + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "CoreTests", dependencies: ["Core"], swiftSettings: typeCheckBudget),
    ]
)
