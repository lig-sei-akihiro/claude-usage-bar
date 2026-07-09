import AppKit
import Combine
import ClaudeUsageBarCore

/// Owns the `NSStatusItem`. Renders the color-coded bar title from
/// `BarTitleFormatter` (requirement #4), runs the refresh timer keyed off
/// `SettingsStore.refreshInterval`, drives `AppModel.snapshot`, and shows the
/// popover (`PopoverView`) / settings window (`SettingsView`).
///
/// Implemented by the App-menubar agent. Contract:
/// - Hold the `AppModel`; wire `model.refreshAction/openSettingsAction/quitAction`.
/// - On each refresh: set `model.isRefreshing`, call `UsageService().snapshot()`,
///   store into `model.snapshot`, then rebuild the bar title.
/// - Bar title: `BarTitleFormatter.make(from:settings:)`; map `BarSeverity` to a
///   text color via `NSStatusItem.button?.attributedTitle`. Respect
///   `settings.showBarText` (hide text → show only an icon/symbol).
/// - Observe `settings.objectWillChange` to re-render the title immediately when the
///   user changes display options.
@MainActor
final class StatusItemController {
    init(model: AppModel) {
        // Implemented by the App-menubar agent.
    }
}
