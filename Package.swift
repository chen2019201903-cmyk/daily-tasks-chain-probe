// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ProbeCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "ProbeCore", targets: ["ProbeCore"])],
    targets: [
        .target(name: "ProbeCore", path: "Sources/ProbeCore"),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"], path: "Tests/ProbeCoreTests")
    ]
)
