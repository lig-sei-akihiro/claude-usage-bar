import Combine
import Foundation
import ClaudeUsageBarCore

/// How often the app refreshes usage. `manual` disables the timer.
enum RefreshInterval: Int, CaseIterable, Identifiable {
    case manual = 0
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case fifteenMinutes = 900

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .oneMinute: return "1 min"
        case .twoMinutes: return "2 min"
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        }
    }
}

/// UserDefaults-backed, observable settings. Maps persisted keys onto the Core
/// `DisplaySettings` value type consumed by `BarTitleFormatter`. Owned by the
/// foundation (shared by StatusItemController and SettingsView) so those two can be
/// implemented in parallel without touching the same file.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    private enum Key {
        static let showBarText = "showBarText"
        static let barMetric = "barMetric"
        static let percentBasis = "percentBasis"
        static let showResetCountdown = "showResetCountdown"
        static let showPercentSign = "showPercentSign"
        static let showMetricLabel = "showMetricLabel"
        static let accountMode = "accountMode"
        static let pinnedEmail = "pinnedEmail"
        static let refreshInterval = "refreshInterval"
    }

    // MARK: Bar display (requirement #6 — all of #4 is toggleable)

    @Published var showBarText: Bool { didSet { defaults.set(showBarText, forKey: Key.showBarText) } }
    @Published var barMetric: BarMetric { didSet { defaults.set(barMetric.rawValue, forKey: Key.barMetric) } }
    @Published var percentBasis: PercentBasis { didSet { defaults.set(percentBasis.rawValue, forKey: Key.percentBasis) } }
    @Published var showResetCountdown: Bool { didSet { defaults.set(showResetCountdown, forKey: Key.showResetCountdown) } }
    @Published var showPercentSign: Bool { didSet { defaults.set(showPercentSign, forKey: Key.showPercentSign) } }
    @Published var showMetricLabel: Bool { didSet { defaults.set(showMetricLabel, forKey: Key.showMetricLabel) } }
    @Published var accountMode: AccountBarMode { didSet { defaults.set(accountMode.rawValue, forKey: Key.accountMode) } }
    @Published var pinnedEmail: String? { didSet { defaults.set(pinnedEmail, forKey: Key.pinnedEmail) } }

    // MARK: Refresh

    @Published var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = DisplaySettings.default

        self.showBarText = defaults.object(forKey: Key.showBarText) as? Bool ?? d.showBarText
        self.barMetric = (defaults.string(forKey: Key.barMetric).flatMap(BarMetric.init(rawValue:))) ?? d.barMetric
        self.percentBasis = (defaults.string(forKey: Key.percentBasis).flatMap(PercentBasis.init(rawValue:))) ?? d.percentBasis
        self.showResetCountdown = defaults.object(forKey: Key.showResetCountdown) as? Bool ?? d.showResetCountdown
        self.showPercentSign = defaults.object(forKey: Key.showPercentSign) as? Bool ?? d.showPercentSign
        self.showMetricLabel = defaults.object(forKey: Key.showMetricLabel) as? Bool ?? d.showMetricLabel
        self.accountMode = (defaults.string(forKey: Key.accountMode).flatMap(AccountBarMode.init(rawValue:))) ?? d.accountMode
        self.pinnedEmail = defaults.string(forKey: Key.pinnedEmail)
        self.refreshInterval = RefreshInterval(rawValue: defaults.object(forKey: Key.refreshInterval) as? Int ?? RefreshInterval.twoMinutes.rawValue) ?? .twoMinutes
    }

    /// The Core value type the formatter consumes.
    var displaySettings: DisplaySettings {
        DisplaySettings(
            showBarText: showBarText,
            barMetric: barMetric,
            percentBasis: percentBasis,
            showResetCountdown: showResetCountdown,
            showPercentSign: showPercentSign,
            showMetricLabel: showMetricLabel,
            accountMode: accountMode,
            pinnedEmail: pinnedEmail
        )
    }
}
