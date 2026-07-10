import Foundation

/// Date helpers for reset times. Kept in Core so both the bar formatter and the
/// popover render identical strings.
public enum DateFormatting {
    /// JST "M/d HH:mm" with seconds rounded to the nearest minute — mirrors the
    /// `jst()` helper in `claude-usage-all` (…59:59.8 rounds up to :00).
    public static func jstResetString(_ date: Date?) -> String {
        guard let date else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let rounded = date.addingTimeInterval(30)
        let c = cal.dateComponents([.month, .day, .hour, .minute], from: rounded)
        return String(format: "%d/%d %02d:%02d", c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// JST "HH:mm" only (no date) — compact reset clock time for the menu bar.
    public static func jstResetShortTime(_ date: Date?) -> String {
        guard let date else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let rounded = date.addingTimeInterval(30)
        let c = cal.dateComponents([.hour, .minute], from: rounded)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Compact time-until countdown: "3h12m", "48m", or "now" when already elapsed.
    public static func countdownString(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return "now" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        return h > 0 ? "\(h)h\(m)m" : "\(m)m"
    }
}
