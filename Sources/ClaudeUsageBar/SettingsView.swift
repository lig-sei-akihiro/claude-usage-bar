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
        Form {
            Section {
                LabeledContent("Menu bar shows") {
                    Text(previewText)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Section("Menu Bar") {
                Toggle("Show text in menu bar", isOn: $settings.showBarText)

                Picker("Metric", selection: $settings.barMetric) {
                    ForEach(BarMetric.allCases, id: \.self) { metric in
                        Text(Self.label(for: metric)).tag(metric)
                    }
                }
                Picker("Show", selection: $settings.percentBasis) {
                    Text("Remaining").tag(PercentBasis.remaining)
                    Text("Used").tag(PercentBasis.used)
                }
                Toggle("Metric label", isOn: $settings.showMetricLabel)
                Toggle("Percent sign", isOn: $settings.showPercentSign)
                Toggle("Reset countdown", isOn: $settings.showResetCountdown)
            }
            .disabled(!settings.showBarText)

            Section("Accounts") {
                Picker("Account", selection: $settings.accountMode) {
                    Text("Active (most constrained)").tag(AccountBarMode.active)
                    Text("Pinned account").tag(AccountBarMode.pinned)
                    Text("All accounts").tag(AccountBarMode.all)
                }
                if settings.accountMode == .pinned {
                    Picker("Pinned", selection: $settings.pinnedEmail) {
                        Text("—").tag(String?.none)
                        ForEach(accounts) { account in
                            Text(account.email).tag(String?.some(account.email))
                        }
                    }
                }
            }

            Section("Refresh") {
                Picker("Interval", selection: $settings.refreshInterval) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
    }

    /// Live sample of the composed bar title, using the first account if present.
    private var previewText: String {
        let snapshot = UsageSnapshot(accounts: accounts, generatedAt: Date())
        let title = BarTitleFormatter.make(from: snapshot, settings: settings.displaySettings)
        return title.text.isEmpty ? "(icon only)" : title.text
    }

    static func label(for metric: BarMetric) -> String {
        switch metric {
        case .session: return "Session (5h)"
        case .weeklyAll: return "Week (all)"
        case .weeklyFable: return "Week (Fable)"
        case .mostConstrained: return "Most constrained"
        }
    }
}
