import Foundation

// MARK: - 表示設定(contract)
//
// メニューバーのタイトルに何を表示するか — iStat Menus 風に完全に設定可能。フォーマッタを
// ユニットテストできるよう Core 内の素の値型とし、App レイヤーの SettingsStore が
// UserDefaults をこれにマッピングする。

/// どの使用量ウィンドウをバータイトルに反映するか。
public enum BarMetric: String, Sendable, CaseIterable, Codable {
    /// 移動する 5 時間のセッションウィンドウ — デフォルト。
    case session
    case weeklyAll
    case weeklyFable
    /// 現在アカウントのレート制限を決定づけているウィンドウ。
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

/// 表示するパーセントが使用済み予算か残り予算か。
public enum PercentBasis: String, Sendable, CaseIterable, Codable {
    /// 使用済みのパーセント — デフォルト。`claude-usage-all` コマンドと一致する。
    case used
    /// 100 − 使用済み。「残り予算」を好む場合に設定で有効化する。
    case remaining
}

/// 複数アカウントを 1 つのバータイトルにどうまとめるか。
public enum AccountBarMode: String, Sendable, CaseIterable, Codable {
    /// 最も制約の厳しいアカウントを表示する(そのアクティブ/最高値のウィンドウ)。デフォルト。
    case active
    /// email で固定した特定の 1 アカウントを表示する。
    case pinned
    /// 全アカウントを " | " 区切りでコンパクトに表示する。
    case all
}

/// バータイトルがパーセントの後ろに(あれば)どのリセット情報を付加するか。
public enum ResetDisplay: String, Sendable, CaseIterable, Codable {
    /// 何も付けない。デフォルト。
    case none
    /// リセットまでの時間。例: "· 3h12m"。
    case countdown
    /// リセットの時刻(JST)。例: "· 12:49"。
    case time
}

/// バータイトルを決めるための設定項目。すぐ使える妥当なデフォルト値を持つ。
public struct DisplaySettings: Sendable, Equatable, Codable {
    /// バーテキストのマスタートグル。false のときはアイコンのみ表示する。
    public var showBarText: Bool
    public var barMetric: BarMetric
    public var percentBasis: PercentBasis
    /// リセット情報をバーに付加するか/どう付加するか(要件: リセット時刻も表示すること)。
    public var resetDisplay: ResetDisplay
    /// 数値の後ろに "%" 記号を描画する。
    public var showPercentSign: Bool
    /// メトリクスラベルを先頭に付ける。例: "5h "。
    public var showMetricLabel: Bool
    public var accountMode: AccountBarMode
    /// `accountMode == .pinned` のときに表示する email。
    public var pinnedEmail: String?
    /// この使用率以上でテキストがオレンジ(警告)になる。0...100。
    public var warningThreshold: Double
    /// この使用率以上でテキストが赤(重大)になる。設定 UI 上は `warningThreshold` 以上に
    /// 保たれるが、フォーマッタはどの順序でも許容する(同値のときは critical が優先)。
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
