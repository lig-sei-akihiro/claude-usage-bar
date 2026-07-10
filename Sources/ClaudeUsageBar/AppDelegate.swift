import AppKit
import ClaudeUsageBarCore

/// App lifecycle: on launch, create the `SettingsStore`, `AppModel`, and
/// `StatusItemController` (retaining them), then trigger the first refresh.
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
