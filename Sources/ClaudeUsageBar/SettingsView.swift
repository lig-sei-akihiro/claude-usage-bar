import SwiftUI
import ClaudeUsageBarCore

/// iStat-Menus-style settings for what the bar shows (requirements #4 & #6):
/// master toggle, metric, remaining/used, reset countdown, account mode + pin,
/// and refresh cadence. Implemented by the App-UI agent.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Text("TODO")
    }
}
