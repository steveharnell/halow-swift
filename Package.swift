// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HaLowSwift",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "halow-probe", targets: ["HaLowProbe"]),
        .executable(name: "HaLowSwift", targets: ["HaLowApp"])
    ],
    targets: [
        .target(name: "HaLowCore"),
        .executableTarget(name: "HaLowProbe", dependencies: ["HaLowCore"]),
        .executableTarget(name: "HaLowApp", dependencies: ["HaLowCore"])
    ]
)
