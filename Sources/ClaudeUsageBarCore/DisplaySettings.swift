import Foundation

// MARK: - Display settings (contract)
//
// What the menu bar title shows. Requirement #6: the #4 bar display is fully
// configurable, iStat-Menus style. This is a plain value type in Core so the
// formatter can be unit-tested; the App layer's SettingsStore maps UserDefaults
// onto this.

/// Which usage window feeds the bar title.
public enum BarMetric: String, Sendable, CaseIterable, Codable {
    /// The rolling 5-hour session window — the default (requirement #4).
    case session
    case weeklyAll
    case weeklyFable
    /// Whichever window is currently rate-limiting the account.
    case mostConstrained

    public var shortLabel: String {
        switch self {
        case .session: return "5h"
        case .weeklyAll: return "W"
        case .weeklyFable: return "WF"
        case .mostConstrained: return "!"
        }
    }
}

/// Whether the percent shown is budget used or budget remaining.
public enum PercentBasis: String, Sendable, CaseIterable, Codable {
    /// The percent used — the default, matching the `claude-usage-all` command.
    case used
    /// 100 − used. Opt-in via settings for those who prefer "budget left".
    case remaining
}

/// How multiple accounts collapse into a single bar title.
public enum AccountBarMode: String, Sendable, CaseIterable, Codable {
    /// Show the most-constrained account (its active/highest window). Default.
    case active
    /// Show one specific account, pinned by email.
    case pinned
    /// Show every account compactly, separated by " | ".
    case all
}

/// The knobs that decide the bar title. Sensible defaults satisfy requirement #4
/// (5-hour remaining, visible at a glance) out of the box.
public struct DisplaySettings: Sendable, Equatable, Codable {
    /// Master toggle for the bar text (requirement #6). When false, only an icon shows.
    public var showBarText: Bool
    public var barMetric: BarMetric
    public var percentBasis: PercentBasis
    /// Append the reset countdown, e.g. "5h 42% · 3h12m".
    public var showResetCountdown: Bool
    /// Render the "%" sign after the number.
    public var showPercentSign: Bool
    /// Prefix the metric label, e.g. "5h ".
    public var showMetricLabel: Bool
    public var accountMode: AccountBarMode
    /// Email to show when `accountMode == .pinned`.
    public var pinnedEmail: String?

    public init(
        showBarText: Bool = true,
        barMetric: BarMetric = .session,
        percentBasis: PercentBasis = .used,
        showResetCountdown: Bool = false,
        showPercentSign: Bool = true,
        showMetricLabel: Bool = true,
        accountMode: AccountBarMode = .active,
        pinnedEmail: String? = nil
    ) {
        self.showBarText = showBarText
        self.barMetric = barMetric
        self.percentBasis = percentBasis
        self.showResetCountdown = showResetCountdown
        self.showPercentSign = showPercentSign
        self.showMetricLabel = showMetricLabel
        self.accountMode = accountMode
        self.pinnedEmail = pinnedEmail
    }

    public static let `default` = DisplaySettings()
}
