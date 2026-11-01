// swift-tools-version:5.10
// linux build of yuzu. the mac app is built from project.yml (xcodegen), not from this file.
import PackageDescription

let package = Package(
    name: "yuzu",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "yuzu", targets: ["yuzu"]),
        .library(name: "YuzuLinuxCore", targets: ["YuzuLinuxCore"]),
    ],
    targets: [
        .target(
            name: "YuzuLinuxCore",
            path: "linux/Sources/YuzuLinuxCore",
            // Markdown.swift uses /regex/ literals, which the xcode project enables by default
            swiftSettings: [.enableUpcomingFeature("BareSlashRegexLiterals")]
            // Shared/ holds symlinks to files in Yuzu/Jobs that only import Foundation,
            // so the mac app and the linux build compile the same source.
        ),
        .executableTarget(
            name: "yuzu",
            dependencies: ["YuzuLinuxCore"],
            path: "linux/Sources/yuzu"
        ),
        .testTarget(
            name: "YuzuLinuxCoreTests",
            dependencies: ["YuzuLinuxCore"],
            path: "linux/Tests/YuzuLinuxCoreTests"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
