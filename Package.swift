// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Notchy",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotchyCore"),
        .executableTarget(name: "Notchy", dependencies: ["NotchyCore"]),
        .executableTarget(name: "NotchyChecks", dependencies: ["NotchyCore"]),
    ]
)
