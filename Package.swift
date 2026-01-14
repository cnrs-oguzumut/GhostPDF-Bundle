// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhostPDF+",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "GhostPDF+",
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency=minimal")
            ]
        )
    ]
)
