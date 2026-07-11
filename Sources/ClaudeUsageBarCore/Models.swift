import Foundation

// MARK: - 使用状況モデル（契約）
//
// これらの値型は、データ層・フォーマッタ・UI の間で共有される契約である。
// Core をユニットテスト可能に保つため、意図的に AppKit へ依存しない。
// GET /api/oauth/usage の `limits[]` を `claude-usage-all` が解釈した構造を写している。

/// `limits[]` の 1 エントリが表す使用状況ウィンドウの正規化された種別。
public enum RateWindowKind: String, Sendable, Codable {
    /// `kind == "session"` — 5 時間単位でスライドするウィンドウ。
    case session
    /// `kind == "weekly_all"` — 全モデル合算の 7 日間ウィンドウ。
    case weeklyAll
    /// `kind == "weekly_scoped"` — モデル単位の週次ウィンドウ（例: Fable）。
    case weeklyScoped
}

/// アカウントの 1 つの使用状況ウィンドウ（セッション / 週次）。
public struct RateWindow: Sendable, Equatable, Codable {
    public var kind: RateWindowKind
    /// 画面表示用のラベル。例: "Session (5h)"、"Week (all)"、"Week (Fable)"。
    public var label: String
    /// 使用済みの利用率パーセント、0...100（`percent` 由来）。API はサブスクリプション
    /// プランについて絶対的なトークン数ではなく利用率パーセントを返す。
    public var usedPercent: Double
    /// `resets_at` を絶対時刻として解釈した値（API は UTC の ISO-8601 で送る）。
    public var resetsAt: Date?
    /// `severity` — "normal" / "warning"（warning は概ね 85% 以上）。
    public var severity: String?
    /// `is_active` — 現在このアカウントのレート制限を実際に効かせているウィンドウ。
    public var isActive: Bool
    /// `weeklyScoped` ウィンドウにおける `scope.model.display_name`（例: "Fable"）。
    public var scopeModel: String?

    public init(
        kind: RateWindowKind,
        label: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        severity: String? = nil,
        isActive: Bool = false,
        scopeModel: String? = nil
    ) {
        self.kind = kind
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.severity = severity
        self.isActive = isActive
        self.scopeModel = scopeModel
    }

    /// 残り使用可能量をパーセントで表した値。0...100 にクランプする。
    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    public var isWarning: Bool { (severity ?? "").lowercased() == "warning" }
}

/// 認証済みアカウント 1 つ（email）ぶんの使用状況。1 つの email は複数の設定フォルダ
/// （`~/.claude_main`、`~/.claude_sub`、…）で共有され得るが、ここでは 1 つにまとめる。
public struct AccountUsage: Sendable, Equatable, Codable, Identifiable {
    public var email: String
    /// この認証情報を共有する設定フォルダの短縮名。例: ["main", "sub"]。
    public var folders: [String]
    public var windows: [RateWindow]
    /// 探索または取得に失敗した場合に非 nil となる（認証切れ、トークンなし、HTTP エラー）。
    public var error: String?
    public var fetchedAt: Date?

    public var id: String { email }

    public init(
        email: String,
        folders: [String],
        windows: [RateWindow] = [],
        error: String? = nil,
        fetchedAt: Date? = nil
    ) {
        self.email = email
        self.folders = folders
        self.windows = windows
        self.error = error
        self.fetchedAt = fetchedAt
    }

    public var session: RateWindow? { windows.first { $0.kind == .session } }
    public var weeklyAll: RateWindow? { windows.first { $0.kind == .weeklyAll } }
    public var weeklyFable: RateWindow? {
        windows.first { $0.kind == .weeklyScoped && ($0.scopeModel ?? "").lowercased() == "fable" }
    }

    /// 現在このアカウントのレート制限を効かせているウィンドウ（`is_active`）。なければ使用率が最も高いウィンドウ。
    public var mostConstrainedWindow: RateWindow? {
        if let active = windows.first(where: { $0.isActive }) { return active }
        return windows.max(by: { $0.usedPercent < $1.usedPercent })
    }

    public var hasError: Bool { error != nil }
}

/// 探索できた全アカウントを横断した完全なスナップショット。`UsageService` が生成する。
public struct UsageSnapshot: Sendable, Equatable, Codable {
    public var accounts: [AccountUsage]
    public var generatedAt: Date

    public init(accounts: [AccountUsage], generatedAt: Date) {
        self.accounts = accounts
        self.generatedAt = generatedAt
    }

    public static let empty = UsageSnapshot(accounts: [], generatedAt: .distantPast)

    /// 新しいデータが取れずにエラーになったばかりのアカウント（例: 一時的な HTTP 429）について、
    /// 直近既知のウィンドウを引き継ぐ。これにより一過性の不調でバーが "?" に化けないようにする。
    /// 一度もデータを持っていないアカウントはエラーのまま残す。
    public func retainingWindows(from previous: UsageSnapshot) -> UsageSnapshot {
        let merged = accounts.map { acc -> AccountUsage in
            guard acc.hasError, acc.windows.isEmpty,
                  let prev = previous.accounts.first(where: { $0.email == acc.email }),
                  !prev.windows.isEmpty
            else { return acc }
            return AccountUsage(
                email: acc.email, folders: acc.folders, windows: prev.windows,
                error: nil, fetchedAt: prev.fetchedAt)
        }
        return UsageSnapshot(accounts: merged, generatedAt: generatedAt)
    }
}

// MARK: - メニューバータイトル（契約）

/// メニューバーのタイトル色を決める深刻度。
public enum BarSeverity: String, Sendable, Codable {
    case normal
    case warning
    case critical
    /// 表示中のアカウントで取得または認証に失敗した状態。
    case error
    /// まだ新しいデータがない、または全アカウントが古い状態。
    case stale
}

/// 組み立て済みのメニューバータイトル。ステータス項目に描画するテキストと、色を決める深刻度からなる。
public struct BarTitle: Sendable, Equatable {
    public var text: String
    public var severity: BarSeverity

    public init(text: String, severity: BarSeverity) {
        self.text = text
        self.severity = severity
    }

    /// 初回の更新が完了するまで表示するプレースホルダ。
    public static let placeholder = BarTitle(text: "…", severity: .stale)
}

/// `.all` モードで積み重ねて表示するタイトルの 1 行。行ごとに深刻度を持たせ、メニューバー上で
/// アカウント行を個別に色付けできるようにする。
public struct StackedLine: Sendable, Equatable {
    public var text: String
    public var severity: BarSeverity

    public init(text: String, severity: BarSeverity) {
        self.text = text
        self.severity = severity
    }
}
