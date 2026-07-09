import AppKit
import Combine
import ClaudeUsageBarCore

/// Owns the `NSStatusItem`. Renders the color-coded bar title from
/// `BarTitleFormatter` (requirement #4), runs the refresh timer, and shows the
/// popover with the per-account list. Implemented by the App-menubar agent.
@MainActor
final class StatusItemController {
    init(settings: SettingsStore) {
        // Implemented by the App-menubar agent.
    }
}
