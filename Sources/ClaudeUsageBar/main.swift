import AppKit

// メニューバー専用アプリ: `.accessory` にすると Dock アイコンもメインウィンドウも持たず、
// ステータスアイテムだけになる。SPM の実行ファイルとしてビルドするため、SwiftUI の
// `@main` シーンは使わず NSApplication を直接ブートストラップする。
// トップレベルの実行コードは起動時にメインスレッドで走るため、ここで MainActor 分離を
// 前提にしても安全（AppDelegate は @MainActor）。
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
