// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhostPDF+",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "GhostPDF+",
            path: "Sources",
            resources: [.process("Resources")],
            swiftSettings: [
                // Whole module optimization for better inlining and dead code elimination
                .unsafeFlags(["-whole-module-optimization"], .when(configuration: .release)),
                
                // Cross-module optimization (safe LTO alternative)
                .unsafeFlags(["-cross-module-optimization"], .when(configuration: .release)),
                
                // Enable all optimizations with size preference
                .unsafeFlags(["-O"], .when(configuration: .release)),
            ],
            linkerSettings: [
                // Strip symbols and enable dead code stripping at link time
                .unsafeFlags(["-Xlinker", "-dead_strip"], .when(configuration: .release)),
                .unsafeFlags(["-Xlinker", "-x"], .when(configuration: .release)),  // Strip local symbols
            ]
        )
    ]
)
