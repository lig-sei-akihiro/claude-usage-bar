import Foundation

/// スナップショットと表示設定からメニューバータイトルを組み立てる。どのアカウントとどの
/// ウィンドウを表示するか、残量と使用量のどちらを見せるか、そして深刻度の色を決める。
///
/// 契約:
/// - `settings.showBarText` を尊重する（false でも呼び出し側はアイコン表示を望む場合がある）。
/// - `accountMode`: `.active` → 最も制約の厳しいアカウント。`.pinned` → `pinnedEmail` に
///   一致するアカウント（見つからなければ active にフォールバック）。`.all` → 1 行 1 アカウントの
///   複数行タイトル（制約の厳しい上位 2 件まで）で、各行にラベルを付ける。
/// - `barMetric` がウィンドウを選ぶ（`.mostConstrained` はそのアカウントの active/最高使用率を使う）。
/// - `percentBasis`: `.remaining` は `remainingPercent` を表示（既定）、`.used` は `usedPercent` を表示。
/// - 任意で指標ラベルの接頭辞（BarMetric.shortLabel）とリセットまでのカウントダウンの接尾辞を付ける。
/// - 深刻度: 表示中アカウントがエラーなら `.error`。使用率が `settings.criticalThreshold` 以上なら
///   `.critical`。severity=="warning" か使用率が `settings.warningThreshold` 以上なら `.warning`。
///   まだデータがなければ `.stale`。いずれでもなければ `.normal`。
public enum BarTitleFormatter {
    /// ステータス項目に描画する単一のタイトルを組み立てる。
    public static func make(from snapshot: UsageSnapshot, settings: DisplaySettings, now: Date = Date()) -> BarTitle {
        if settings.accountMode == .all {
            return makeAll(from: snapshot, settings: settings, now: now)
        }

        guard let account = selectedAccount(from: snapshot, settings: settings) else {
            return BarTitle(text: "", severity: .stale)
        }

        let window = pickWindow(for: account, metric: settings.barMetric)
        let sev = severity(account: account, window: window, settings: settings)

        guard settings.showBarText else { return BarTitle(text: "", severity: sev) }

        var text = valueFragment(window: window, settings: settings)
        if let window { text += resetSuffix(window: window, settings: settings, now: now) }
        return BarTitle(text: text, severity: sev)
    }

    /// `.active`/`.pinned` モードでバーが代表するアカウントを選ぶ。
    /// ユニットテスト用、およびポップオーバーのハイライトから再利用するために公開している。
    public static func selectedAccount(from snapshot: UsageSnapshot, settings: DisplaySettings) -> AccountUsage? {
        guard !snapshot.accounts.isEmpty else { return nil }

        // エラーになったアカウントは、ウィンドウをまだ保持していない限り使用率 0 として扱う。
        let active = snapshot.accounts.max {
            ($0.mostConstrainedWindow?.usedPercent ?? 0) < ($1.mostConstrainedWindow?.usedPercent ?? 0)
        }

        switch settings.accountMode {
        case .pinned:
            if let email = settings.pinnedEmail,
               let pinned = snapshot.accounts.first(where: { $0.email == email }) {
                return pinned
            }
            return active
        case .active, .all:
            return active
        }
    }

    /// バーのゲージが表す使用済み割合（0...1）。表示中アカウントについて `barMetric` が選んだ
    /// ウィンドウの値、または `.all` モードでは全アカウント中の最悪値（最大）。使えるウィンドウが
    /// なければ `nil`。メニューバーのグリフとポップオーバーのヘッダーバッジが同じ値を追えるよう、
    /// 両者で共有する。
    public static func representativeFraction(from snapshot: UsageSnapshot, settings: DisplaySettings) -> Double? {
        if settings.accountMode == .all {
            return snapshot.accounts
                .compactMap { pickWindow(for: $0, metric: settings.barMetric)?.usedPercent }
                .max()
                .map { $0 / 100 }
        }
        guard let account = selectedAccount(from: snapshot, settings: settings),
              let window = pickWindow(for: account, metric: settings.barMetric) else { return nil }
        return window.usedPercent / 100
    }

    // MARK: - 内部

    /// `.all` モード: 1 行 1 アカウントにラベルを付けた複数行タイトル。アカウントラベル順
    /// （例: "sub" より前に "main"）で並べ、2 行までに制限する。行はレンダラが積み重ねられるよう
    /// "\n" で連結する。
    private static func makeAll(from snapshot: UsageSnapshot, settings: DisplaySettings, now: Date) -> BarTitle {
        let lines = allLines(from: snapshot, settings: settings, now: now)
        guard !lines.isEmpty else { return BarTitle(text: "", severity: .stale) }

        // 深刻度は表示する（最大 2 行の）行だけでなく全アカウントにわたって評価する。これにより
        // `representativeFraction` と同じ集合を追う。表示されていない高使用率のアカウントがあっても、
        // グリフの色をゲージの塗りに合わせられる。
        let worst = snapshot.accounts
            .map { severity(account: $0, window: pickWindow(for: $0, metric: settings.barMetric), settings: settings) }
            .reduce(BarSeverity.normal, worseOf)
        let text = settings.showBarText ? lines.map(\.text).joined(separator: "\n") : ""
        return BarTitle(text: text, severity: worst)
    }

    /// `.all` モードで表示するアカウントごとの行。各行が **それ自身の** 深刻度を持つ
    /// （アイコン/ゲージは最悪値/最大を使う一方で、レンダラが行ごとに独立して色付けできるようにするため）。
    /// ラベル順に並べ、2 件までに制限する。アカウントのないスナップショットでは空になる。
    public static func allLines(from snapshot: UsageSnapshot, settings: DisplaySettings, now: Date = Date()) -> [StackedLine] {
        snapshot.accounts
            .sorted { accountLabel($0) < accountLabel($1) }
            .prefix(2)
            .map { account in
                let window = pickWindow(for: account, metric: settings.barMetric)
                let label = accountLabel(account)
                var text = label.isEmpty ? "" : label + " "
                text += valueFragment(window: window, settings: settings)
                if let window { text += resetSuffix(window: window, settings: settings, now: now) }
                return StackedLine(text: text, severity: severity(account: account, window: window, settings: settings))
            }
    }

    /// 積み重ね表示の行でアカウントを識別する短いラベル。設定フォルダ名を使い、なければ email の
    /// ローカル部にフォールバックする。無名の `"default"` フォルダ（素の `~/.claude`）は決して
    /// 表示しない。default 単独のアカウントにはラベルを付けない。
    private static func accountLabel(_ account: AccountUsage) -> String {
        let named = account.folders.filter { $0 != "default" }
        if !named.isEmpty { return named.joined(separator: "/") }
        // 名前付きフォルダがない場合。フォルダが 1 つもなければ email のローカル部に
        // フォールバックする。唯一のフォルダが "default" だったなら何も表示しない。
        if account.folders.isEmpty {
            if let at = account.email.firstIndex(of: "@") { return String(account.email[..<at]) }
            return account.email
        }
        return ""
    }

    /// 指標値の断片（ラベル + 数値 + % 記号）。カウントダウンの接尾辞は含まない。
    private static func valueFragment(window: RateWindow?, settings: DisplaySettings) -> String {
        var s = ""
        if settings.showMetricLabel { s += settings.barMetric.shortLabel + " " }
        if let window {
            let value = settings.percentBasis == .remaining ? window.remainingPercent : window.usedPercent
            s += String(Int(value.rounded()))
        } else {
            s += "?"
        }
        if settings.showPercentSign { s += "%" }
        return s
    }

    /// `settings.resetDisplay` に従って断片に追記するリセット情報。
    private static func resetSuffix(window: RateWindow, settings: DisplaySettings, now: Date) -> String {
        switch settings.resetDisplay {
        case .none:
            return ""
        case .countdown:
            let cd = DateFormatting.countdownString(to: window.resetsAt, now: now)
            return cd.isEmpty ? "" : " · \(cd)"
        case .time:
            let t = DateFormatting.jstResetShortTime(window.resetsAt)
            return t.isEmpty ? "" : " · \(t)"
        }
    }

    private static func pickWindow(for account: AccountUsage, metric: BarMetric) -> RateWindow? {
        switch metric {
        case .session: return account.session
        case .weeklyAll: return account.weeklyAll
        case .weeklyFable: return account.weeklyFable
        case .mostConstrained: return account.mostConstrainedWindow
        }
    }

    private static func severity(account: AccountUsage, window: RateWindow?, settings: DisplaySettings) -> BarSeverity {
        if account.hasError { return .error }
        guard let window else { return .stale }
        return windowSeverity(window, warningAt: settings.warningThreshold, criticalAt: settings.criticalThreshold)
    }

    /// 設定された使用率パーセントのしきい値に照らした、単一ウィンドウの深刻度。
    /// サーバー側の `severity=="warning"` は、それでも最低でも `.warning` まで引き上げる。
    /// 深刻度しきい値の唯一の正となる場所であり、メニューバータイトルとポップオーバーの両方が
    /// これを呼ぶため、しきい値を変えれば両者が一緒に動く。
    /// 比較は使用率パーセントに対して行うため（残り ≤ 5 ⟺ 使用 ≥ 95）、表示が残量基準か使用量基準かに
    /// 依存しない。
    public static func windowSeverity(_ window: RateWindow, warningAt warning: Double, criticalAt critical: Double) -> BarSeverity {
        if window.usedPercent >= critical { return .critical }
        if window.isWarning || window.usedPercent >= warning { return .warning }
        return .normal
    }

    private static func worseOf(_ a: BarSeverity, _ b: BarSeverity) -> BarSeverity {
        rank(a) >= rank(b) ? a : b
    }

    private static func rank(_ s: BarSeverity) -> Int {
        switch s {
        case .normal: return 0
        case .stale: return 1
        case .warning: return 2
        case .critical: return 3
        case .error: return 4
        }
    }
}
