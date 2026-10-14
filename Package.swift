// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Monte",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Monte",
            path: "Sources/Monte",
            exclude: ["Resources"]
        )
    ]
)
