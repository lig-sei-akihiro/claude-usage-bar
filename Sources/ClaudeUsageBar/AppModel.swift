import AppKit
import Combine
import ClaudeUsageBarCore

/// Shared, observable app state + actions. This is the single interface between the
/// menu-bar layer (StatusItemController) and the SwiftUI views (PopoverView /
/// SettingsView) so they can be built independently: views only read this model and
/// call its actions; the controller owns the refresh loop and wires the actions.
@MainActor
final class AppModel: ObservableObject {
    /// Latest usage across all accounts. Views observe this; the controller sets it.
    @Published var snapshot: UsageSnapshot = .empty
    /// True while a refresh is in flight (for a spinner in the popover).
    @Published var isRefreshing: Bool = false

    let settings: SettingsStore

    // Actions are injected by StatusItemController so views stay decoupled from it.
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
