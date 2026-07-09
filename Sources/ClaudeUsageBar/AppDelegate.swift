import AppKit
import ClaudeUsageBarCore

/// App lifecycle. Implemented by the App-menubar agent: on launch, create the
/// `SettingsStore`, the `AppModel`, and the `StatusItemController` (retaining them),
/// then trigger the first refresh.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Implemented by the App-menubar agent.
    }
}
