import AppKit
import SwiftUI
import ClaudeUsageBarCore

/// iStat Menus 風の設定。ログイン時起動、バーの metric / 残量か使用量か / reset の表示 /
/// ラベルの各トグル、アカウントモードとピン留め、リフレッシュ間隔。`accounts` は pin の
/// ピッカーを埋めるために開いた時点で渡される。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    var accounts: [AccountUsage] = []
    /// システムの login-item の状態 (UserDefault ではなく SMAppService が保持する)。開いた時点で初期値を入れる。
    @State private var launchAtLogin = LoginItem.isEnabled
    /// `body` の再評価ごとに設定ファイルを読まないよう 1 度だけ解決する。
    @State private var teamclaudePort = TeamclaudeConfig.defaultPort

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
                    if let version = Self.appVersion {
                        Text("v\(version)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                    }
            }

            Section("Usage Source") {
                Picker("Source", selection: $settings.usageSource) {
                    Text("Claude Code config folders").tag(UsageSourceKind.local)
                    Text("teamclaude pool").tag(UsageSourceKind.teamclaude)
                }
                Text(sourceCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                // ここにはプレビューを置かない。これらの変更に合わせて実際のメニューバーがリアルタイムに更新される。
                // 表示トグルは下の .disabled グループの外に置く。さもないとオフにした時点でトグル自身が
                // 無効化され、二度とオンに戻せなくなる。テキストとアイコンは互いに「最後の 1 つ」を消せない
                // よう相手が唯一の表示要素のときだけ無効化し、メニューバーが空になるのを防ぐ。
                Toggle("Show text in menu bar", isOn: $settings.showBarText)
                    .disabled(!settings.showBarIcon)
                Toggle("Show icon in menu bar", isOn: $settings.showBarIcon)
                    .disabled(!settings.showBarText)

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

            Section("Colors") {
                VStack(alignment: .leading, spacing: 8) {
                    ThresholdSlider(warning: $settings.warningThreshold,
                                    critical: $settings.criticalThreshold)
                    HStack(alignment: .firstTextBaseline) {
                        Text("Text turns orange at \(Int(settings.warningThreshold))% used and red at \(Int(settings.criticalThreshold))%.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") { settings.resetThresholds() }
                            .controlSize(.small)
                            .disabled(settings.thresholdsAreDefault)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Accounts") {
                Picker("Account", selection: accountModeSelection) {
                    if settings.usageSource == .local {
                        Text("Active (most constrained)").tag(AccountBarMode.active)
                    }
                    Text("Pinned account").tag(AccountBarMode.pinned)
                    Text("All accounts").tag(AccountBarMode.all)
                }
                if settings.usageSource == .teamclaude {
                    Text("The pool rotates accounts, so a single most-constrained account is not shown. All accounts is used instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if settings.effectiveAccountMode == .all {
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
        .onAppear { teamclaudePort = TeamclaudeConfig.resolvePort() }
    }

    /// teamclaude 選択中は `.active` の行が無い。永続値のまま束縛すると選択なしになる。
    private var accountModeSelection: Binding<AccountBarMode> {
        Binding(
            get: { settings.effectiveAccountMode },
            set: { settings.accountMode = $0 })
    }

    private var sourceCaption: String {
        switch settings.usageSource {
        case .local:
            return "Reads ~/.claude* config folders and the login keychain."
        case .teamclaude:
            return "Reads http://127.0.0.1:\(teamclaudePort)/teamclaude/quota. Needs teamclaude 1.1.17 or newer, running."
        }
    }

    /// バンドルのマーケティングバージョン (`CFBundleShortVersionString`)。`Scripts/package_app.sh` が
    /// 設定する。素の `swift run` ビルドでは (Info.plist が無いため) `nil` になり、その場合ヘッダーは
    /// バージョン行を単に省略する。
    static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
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
