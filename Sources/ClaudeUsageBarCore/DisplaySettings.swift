import Foundation

// MARK: - Display settings (contract)
//
// What the menu bar title shows — fully configurable, iStat-Menus style. A plain
// value type in Core so the formatter can be unit-tested; the App layer's
// SettingsStore maps UserDefaults onto this.

/// Which usage window feeds the bar title.
public enum BarMetric: String, Sendable, CaseIterable, Codable {
    /// The rolling 5-hour session window — the default.
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

/// What reset info (if any) the bar title appends after the percent.
public enum ResetDisplay: String, Sendable, CaseIterable, Codable {
    /// Nothing. Default.
    case none
    /// Time until reset, e.g. "· 3h12m".
    case countdown
    /// Clock time of the reset (JST), e.g. "· 12:49".
    case time
}

/// The knobs that decide the bar title, with sensible out-of-the-box defaults.
public struct DisplaySettings: Sendable, Equatable, Codable {
    /// Master toggle for the bar text. When false, only an icon shows.
    public var showBarText: Bool
    public var barMetric: BarMetric
    public var percentBasis: PercentBasis
    /// Whether/how to append reset info to the bar (requirement: show reset time too).
    public var resetDisplay: ResetDisplay
    /// Render the "%" sign after the number.
    public var showPercentSign: Bool
    /// Prefix the metric label, e.g. "5h ".
    public var showMetricLabel: Bool
    public var accountMode: AccountBarMode
    /// Email to show when `accountMode == .pinned`.
    public var pinnedEmail: String?
    /// Used-percent at/above which the text turns orange (warning). 0...100.
    public var warningThreshold: Double
    /// Used-percent at/above which the text turns red (critical). Kept ≥ `warningThreshold`
    /// by the settings UI, but the formatter tolerates any order (critical wins the tie).
    public var criticalThreshold: Double

    public init(
        showBarText: Bool = true,
        barMetric: BarMetric = .session,
        percentBasis: PercentBasis = .used,
        resetDisplay: ResetDisplay = .none,
        showPercentSign: Bool = true,
        showMetricLabel: Bool = true,
        accountMode: AccountBarMode = .active,
        pinnedEmail: String? = nil,
        warningThreshold: Double = 85,
        criticalThreshold: Double = 95
    ) {
        self.showBarText = showBarText
        self.barMetric = barMetric
        self.percentBasis = percentBasis
        self.resetDisplay = resetDisplay
        self.showPercentSign = showPercentSign
        self.showMetricLabel = showMetricLabel
        self.accountMode = accountMode
        self.pinnedEmail = pinnedEmail
        self.warningThreshold = warningThreshold
        self.criticalThreshold = criticalThreshold
    }

    public static let `default` = DisplaySettings()
}
