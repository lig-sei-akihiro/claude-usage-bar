import AppKit
import Combine
import ClaudeUsageBarCore

/// アプリ全体で共有する observable な状態とアクション。メニューバー層
/// (StatusItemController) と SwiftUI ビュー (PopoverView / SettingsView) の間の
/// 唯一のインターフェースで、両者を独立して組み立てられるようにする: ビューはこの
/// モデルを読み取ってアクションを呼ぶだけ。リフレッシュループはコントローラーが持ち、
/// アクションの結線もコントローラーが行う。
@MainActor
final class AppModel: ObservableObject {
    /// 全アカウントを横断した最新の使用状況。ビューが監視し、コントローラーが設定する。
    @Published var snapshot: UsageSnapshot = .empty
    /// リフレッシュ実行中は true（ポップオーバーのスピナー用）。
    @Published var isRefreshing: Bool = false

    let settings: SettingsStore

    // アクションは StatusItemController から注入し、ビューがそれと疎結合であるようにする。
    var refreshAction: @MainActor () -> Void = {}
    var openSettingsAction: @MainActor () -> Void = {}
    var quitAction: @MainActor () -> Void = { NSApp.terminate(nil) }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func refresh() { refreshAction() }
    func openSettings() { openSettingsAction() }
    func quit() { quitAction() }
}
