import SwiftUI
import ClaudeUsageBarCore

/// iStat-Menus-style settings for what the bar shows (requirements #4 & #6):
/// master text toggle, metric, remaining/used, reset countdown, account mode + pin
/// (the pin picker lists `model.snapshot.accounts`), and refresh cadence.
///
/// Implemented by the App-UI agent. Reads `model.settings` (an ObservableObject) and
/// `model.snapshot`. Construct as `SettingsView().environmentObject(model)`.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Text("TODO")
    }
}
