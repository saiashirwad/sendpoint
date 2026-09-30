// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "OdinFluidProbe",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OdinFluidProbe", type: .dynamic, targets: ["OdinFluidProbe"])],
    dependencies: [.package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b")],
    targets: [.target(name: "OdinFluidProbe", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])]
)
