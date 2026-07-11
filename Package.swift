// swift-tools-version:5.9
import PackageDescription

// tools version を Swift 5.9 にしておくと、Swift 6 ツールチェーン上でも並行性チェックが
// 緩いままになる。個人用の小さなメニューバーツールには現実的な選択だ。外部依存はゼロで、
// すべてシステムフレームワーク (AppKit, SwiftUI, CryptoKit, Security) を使う。
let package = Package(
    name: "ClaudeUsageBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ClaudeUsageBarCore", targets: ["ClaudeUsageBarCore"]),
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
    ],
    targets: [
        // 純粋なロジック: 設定の検出、Keychain、使用状況 API、整形。AppKit 非依存でユニットテスト可能。
        .target(
            name: "ClaudeUsageBarCore"
        ),
        // メニューバーアプリ: NSStatusItem と、AppKit 経由でホストする SwiftUI のポップオーバー/設定画面。
        .executableTarget(
            name: "ClaudeUsageBar",
            dependencies: ["ClaudeUsageBarCore"]
        ),
        .testTarget(
            name: "ClaudeUsageBarCoreTests",
            dependencies: ["ClaudeUsageBarCore"]
        ),
    ]
)
