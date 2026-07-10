import AppKit
import SwiftUI
import ClaudeUsageBarCore

/// iStat-Menus-style settings: launch-at-login, the bar's metric / remaining-vs-used /
/// reset display / label toggles, account mode + pin, and refresh cadence. `accounts`
/// is passed at open time to populate the pin picker.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var accounts: [AccountUsage] = []
    /// System login-item state (not a UserDefault — SMAppService owns it). Seeded on open.
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Usage Bar")
                            .font(.headline)
                        Text("Claude Code usage in your menu bar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
            }

            Section("Menu Bar") {
                // No preview here — the real menu bar updates live as these change.
                // The master toggle must stay OUTSIDE the .disabled scope, or turning
                // it off disables itself and you can never turn it back on.
                Toggle("Show text in menu bar", isOn: $settings.showBarText)

                Group {
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
                    Picker("Reset", selection: $settings.resetDisplay) {
                        Text("Off").tag(ResetDisplay.none)
                        Text("Countdown").tag(ResetDisplay.countdown)
                        Text("Time").tag(ResetDisplay.time)
                    }
                }
                .disabled(!settings.showBarText)
            }

            Section("Accounts") {
                Picker("Account", selection: $settings.accountMode) {
                    Text("Active (most constrained)").tag(AccountBarMode.active)
                    Text("Pinned account").tag(AccountBarMode.pinned)
                    Text("All accounts").tag(AccountBarMode.all)
                }
                if settings.accountMode == .all {
                    Text("Stacks each account on its own line in the menu bar (max 2).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

    static func label(for metric: BarMetric) -> String {
        switch metric {
        case .session: return "Session (5h)"
        case .weeklyAll: return "Week (all)"
        case .weeklyFable: return "Week (Fable)"
        case .mostConstrained: return "Most constrained"
        }
    }
}
