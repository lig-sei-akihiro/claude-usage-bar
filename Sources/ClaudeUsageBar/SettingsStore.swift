import Combine
import Foundation
import ClaudeUsageBarCore

/// アプリが使用状況をリフレッシュする間隔。`manual` はタイマーを無効にする。
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

/// UserDefaults を裏に持つ observable な設定。永続化したキーを、`BarTitleFormatter` が
/// 使う Core の `DisplaySettings` 値型へマッピングする。
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    private enum Key {
        static let showBarText = "showBarText"
        static let showBarIcon = "showBarIcon"
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

    // MARK: バー表示

    @Published var showBarText: Bool { didSet { defaults.set(showBarText, forKey: Key.showBarText) } }
    /// メニューバーに Clawd グリフ + ゲージを表示するか。テキスト表示とは独立。ただしテキストと
    /// 両方を消すとステータスアイテムが空になるため、UI/描画の双方で少なくとも一方は残す。
    /// グリフ描画は App レイヤー専任のため、Core の `DisplaySettings` には持たせない。
    @Published var showBarIcon: Bool { didSet { defaults.set(showBarIcon, forKey: Key.showBarIcon) } }
    @Published var barMetric: BarMetric { didSet { defaults.set(barMetric.rawValue, forKey: Key.barMetric) } }
    @Published var percentBasis: PercentBasis { didSet { defaults.set(percentBasis.rawValue, forKey: Key.percentBasis) } }
    @Published var resetDisplay: ResetDisplay { didSet { defaults.set(resetDisplay.rawValue, forKey: Key.resetDisplay) } }
    @Published var showPercentSign: Bool { didSet { defaults.set(showPercentSign, forKey: Key.showPercentSign) } }
    @Published var showMetricLabel: Bool { didSet { defaults.set(showMetricLabel, forKey: Key.showMetricLabel) } }
    @Published var accountMode: AccountBarMode { didSet { defaults.set(accountMode.rawValue, forKey: Key.accountMode) } }
    @Published var pinnedEmail: String? { didSet { defaults.set(pinnedEmail, forKey: Key.pinnedEmail) } }

    /// 深刻度の色付けに使う使用率のしきい値。妥当性 (1...99、critical ≥ warning + 1) は
    /// `ThresholdSlider` が保証する。これらの setter は永続化だけを行う。
    @Published var warningThreshold: Double { didSet { defaults.set(warningThreshold, forKey: Key.warningThreshold) } }
    @Published var criticalThreshold: Double { didSet { defaults.set(criticalThreshold, forKey: Key.criticalThreshold) } }

    // MARK: リフレッシュ

    @Published var refreshInterval: RefreshInterval {
        didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = DisplaySettings.default

        self.showBarText = defaults.object(forKey: Key.showBarText) as? Bool ?? d.showBarText
        self.showBarIcon = defaults.object(forKey: Key.showBarIcon) as? Bool ?? true
        self.barMetric = (defaults.string(forKey: Key.barMetric).flatMap(BarMetric.init(rawValue:))) ?? d.barMetric
        self.percentBasis = (defaults.string(forKey: Key.percentBasis).flatMap(PercentBasis.init(rawValue:))) ?? d.percentBasis
        // 製品としての初期値（formatter のテストが固定している Core 中立の
        // DisplaySettings.default とは異なる）: 新規インストールではメトリックラベルを表示せず、
        // リセットは時刻で表示する。既存ユーザーは設定済みの値をそのまま維持する。
        self.resetDisplay = (defaults.string(forKey: Key.resetDisplay).flatMap(ResetDisplay.init(rawValue:))) ?? .time
        self.showPercentSign = defaults.object(forKey: Key.showPercentSign) as? Bool ?? d.showPercentSign
        self.showMetricLabel = defaults.object(forKey: Key.showMetricLabel) as? Bool ?? false
        self.accountMode = (defaults.string(forKey: Key.accountMode).flatMap(AccountBarMode.init(rawValue:))) ?? d.accountMode
        self.pinnedEmail = defaults.string(forKey: Key.pinnedEmail)
        self.refreshInterval = RefreshInterval(rawValue: defaults.object(forKey: Key.refreshInterval) as? Int ?? RefreshInterval.twoMinutes.rawValue) ?? .twoMinutes

        // 永続化したしきい値を妥当な範囲と順序にクランプし、破損値や旧バージョンの値によって
        // スライダー（や色付け）が不正な状態に陥らないようにする:
        // warning ∈ [1, 98]、critical ∈ [warning + 1, 99]。
        let rawW = defaults.object(forKey: Key.warningThreshold) as? Double ?? d.warningThreshold
        let rawC = defaults.object(forKey: Key.criticalThreshold) as? Double ?? d.criticalThreshold
        let warn = min(max(rawW, 1), 98)
        self.warningThreshold = warn
        self.criticalThreshold = min(max(rawC, warn + 1), 99)
    }

    /// 色のしきい値が初期値の 85 / 95 のままかどうか。
    var thresholdsAreDefault: Bool {
        warningThreshold == DisplaySettings.default.warningThreshold
            && criticalThreshold == DisplaySettings.default.criticalThreshold
    }

    /// 色のしきい値を初期値 (warning 85 / critical 95) に戻す。
    func resetThresholds() {
        warningThreshold = DisplaySettings.default.warningThreshold
        criticalThreshold = DisplaySettings.default.criticalThreshold
    }

    /// formatter が使う Core の値型。
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
