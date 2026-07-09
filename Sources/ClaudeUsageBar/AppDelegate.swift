import AppKit

/// App lifecycle. Implemented by the App-menubar agent: on launch, create the
/// `SettingsStore` and `StatusItemController`, then kick off the first refresh.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Implemented by the App-menubar agent.
    }
}
