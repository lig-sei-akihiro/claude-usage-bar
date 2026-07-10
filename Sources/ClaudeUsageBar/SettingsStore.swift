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
/// `DisplaySettings` value type consumed by `BarTitleFormatter`.
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
        static let resetDisplay = "resetDisplay"
        static let accountMode = "accountMode"
        static let pinnedEmail = "pinnedEmail"
        static let refreshInterval = "refreshInterval"
        static let warningThreshold = "warningThreshold"
        static let criticalThreshold = "criticalThreshold"
    }

    // MARK: Bar display

    @Published var showBarText: Bool { didSet { defaults.set(showBarText, forKey: Key.showBarText) } }
    @Published var barMetric: BarMetric { didSet { defaults.set(barMetric.rawValue, forKey: Key.barMetric) } }
    @Published var percentBasis: PercentBasis { didSet { defaults.set(percentBasis.rawValue, forKey: Key.percentBasis) } }
    @Published var resetDisplay: ResetDisplay { didSet { defaults.set(resetDisplay.rawValue, forKey: Key.resetDisplay) } }
    @Published var showPercentSign: Bool { didSet { defaults.set(showPercentSign, forKey: Key.showPercentSign) } }
    @Published var showMetricLabel: Bool { didSet { defaults.set(showMetricLabel, forKey: Key.showMetricLabel) } }
    @Published var accountMode: AccountBarMode { didSet { defaults.set(accountMode.rawValue, forKey: Key.accountMode) } }
    @Published var pinnedEmail: String? { didSet { defaults.set(pinnedEmail, forKey: Key.pinnedEmail) } }

    /// Used-percent thresholds for the severity colours. The `ThresholdSlider` keeps
    /// them valid (1...99, critical ≥ warning + 1); these setters only persist.
    @Published var warningThreshold: Double { didSet { defaults.set(warningThreshold, forKey: Key.warningThreshold) } }
    @Published var criticalThreshold: Double { didSet { defaults.set(criticalThreshold, forKey: Key.criticalThreshold) } }

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
        // Out-of-the-box product defaults (differ from the Core-neutral DisplaySettings.default,
        // which the formatter tests pin): a fresh install shows no metric label and the reset
        // as a clock time. Existing users keep whatever they've already set.
        self.resetDisplay = (defaults.string(forKey: Key.resetDisplay).flatMap(ResetDisplay.init(rawValue:))) ?? .time
        self.showPercentSign = defaults.object(forKey: Key.showPercentSign) as? Bool ?? d.showPercentSign
        self.showMetricLabel = defaults.object(forKey: Key.showMetricLabel) as? Bool ?? false
        self.accountMode = (defaults.string(forKey: Key.accountMode).flatMap(AccountBarMode.init(rawValue:))) ?? d.accountMode
        self.pinnedEmail = defaults.string(forKey: Key.pinnedEmail)
        self.refreshInterval = RefreshInterval(rawValue: defaults.object(forKey: Key.refreshInterval) as? Int ?? RefreshInterval.twoMinutes.rawValue) ?? .twoMinutes

        // Clamp persisted thresholds to a sane range and ordering, so a corrupt or
        // legacy value can't leave the slider (or the colours) in an invalid state:
        // warning ∈ [1, 98], critical ∈ [warning + 1, 99].
        let rawW = defaults.object(forKey: Key.warningThreshold) as? Double ?? d.warningThreshold
        let rawC = defaults.object(forKey: Key.criticalThreshold) as? Double ?? d.criticalThreshold
        let warn = min(max(rawW, 1), 98)
        self.warningThreshold = warn
        self.criticalThreshold = min(max(rawC, warn + 1), 99)
    }

    /// Whether the colour thresholds are still at the out-of-the-box 85 / 95.
    var thresholdsAreDefault: Bool {
        warningThreshold == DisplaySettings.default.warningThreshold
            && criticalThreshold == DisplaySettings.default.criticalThreshold
    }

    /// Restore the colour thresholds to the defaults (85 warning / 95 critical).
    func resetThresholds() {
        warningThreshold = DisplaySettings.default.warningThreshold
        criticalThreshold = DisplaySettings.default.criticalThreshold
    }

    /// The Core value type the formatter consumes.
    var displaySettings: DisplaySettings {
        DisplaySettings(
            showBarText: showBarText,
            barMetric: barMetric,
            percentBasis: percentBasis,
            resetDisplay: resetDisplay,
            showPercentSign: showPercentSign,
            showMetricLabel: showMetricLabel,
            accountMode: accountMode,
            pinnedEmail: pinnedEmail,
            warningThreshold: warningThreshold,
            criticalThreshold: criticalThreshold
        )
    }
}
