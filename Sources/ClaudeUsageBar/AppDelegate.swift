import AppKit
import ClaudeUsageBarCore

/// アプリのライフサイクル: 起動時に `SettingsStore`・`AppModel`・
/// `StatusItemController` を生成して保持し、最初のリフレッシュを実行する。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsStore()
        let model = AppModel(settings: settings)
        controller = StatusItemController(model: model)
        model.refresh()
    }
}
