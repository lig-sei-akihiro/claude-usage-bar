import SwiftUI
import ClaudeUsageBarCore

/// iStat-Menus-style settings for what the bar shows (requirements #4 & #6):
/// master text toggle, metric, remaining/used, reset countdown, metric-label &
/// percent-sign toggles, account mode + pin (the pin picker lists `accounts`), and
/// refresh cadence.
///
/// Implemented by the App-UI agent. Observes `SettingsStore` directly so toggles
/// re-render; `accounts` is a snapshot passed at open time (for the pin picker).
/// The controller constructs it as `SettingsView(settings: model.settings, accounts: model.snapshot.accounts)`.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var accounts: [AccountUsage] = []

    var body: some View {
        Text("TODO")
    }
}
