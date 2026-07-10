// swift-tools-version:5.9
import PackageDescription

// Swift 5.9 tools version keeps concurrency checking lenient on the Swift 6 toolchain,
// which is the pragmatic choice for a small personal menu-bar tool. Zero external
// dependencies — everything is a system framework (AppKit, SwiftUI, CryptoKit, Security).
let package = Package(
    name: "ClaudeUsageBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClaudeUsageBarCore", targets: ["ClaudeUsageBarCore"]),
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
        .executable(name: "ClaudeUsageBarWidget", targets: ["ClaudeUsageBarWidget"]),
    ],
    targets: [
        // Pure logic: config discovery, Keychain, usage API, formatting. No AppKit — unit-testable.
        .target(
            name: "ClaudeUsageBarCore"
        ),
        // The menu bar app: NSStatusItem + SwiftUI popover/settings hosted via AppKit.
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageBarCore"]
        ),
        // WidgetKit widget (packaged into the app as a .appex by Scripts/package_app.sh).
        .executableTarget(
            name: "ClaudeUsageBarWidget",
            dependencies: ["ClaudeUsageBarCore"]
        ),
        .testTarget(
            name: "ClaudeUsageBarCoreTests",
            dependencies: ["ClaudeUsageBarCore"]
        ),
    ]
)
