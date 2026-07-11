import Foundation

/// リセット時刻用の日付ヘルパー。バーのフォーマッタとポップオーバーが同一の文字列を
/// 描画できるよう Core に置いている。
public enum DateFormatting {
    /// JST の "M/d HH:mm"。秒を最も近い分に丸める — `claude-usage-all` の `jst()` ヘルパーと
    /// 同じ挙動(…59:59.8 は :00 に切り上げ)。
    public static func jstResetString(_ date: Date?) -> String {
        guard let date else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let rounded = date.addingTimeInterval(30)
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: rounded)
        return String(format: "%d/%d %02d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// JST の "HH:mm" のみ(日付なし) — メニューバー向けのコンパクトなリセット時刻。
    public static func jstResetShortTime(_ date: Date?) -> String {
        guard let date else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let rounded = date.addingTimeInterval(30)
        let c = cal.dateComponents([.hour, .minute], from: rounded)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 残り時間を表すコンパクトなカウントダウン: "3h12m"、"48m"、既に経過していれば "now"。
    public static func countdownString(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "now" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }
}
