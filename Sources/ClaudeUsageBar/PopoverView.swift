import SwiftUI
import ClaudeUsageBarCore

/// The dropdown content shown when the status item is clicked: one row per account
/// with session/weekly bars and reset times (requirement #5 — multi-account), plus a
/// footer with refresh / settings / quit.
///
/// Implemented by the App-UI agent. Reads everything from the injected `AppModel`
/// (`model.snapshot`, `model.settings`, `model.isRefreshing`) and calls
/// `model.refresh()` / `model.openSettings()` / `model.quit()`. Construct as
/// `PopoverView().environmentObject(model)`.
struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Text("TODO")
    }
}
