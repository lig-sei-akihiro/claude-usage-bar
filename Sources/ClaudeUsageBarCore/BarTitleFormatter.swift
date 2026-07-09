import Foundation

/// Composes the menu bar title from a snapshot + display settings.
///
/// This is the heart of requirements #4/#5/#6: it decides which account and which
/// window to show, whether to show remaining vs used, and the severity color.
///
/// Contract:
/// - Respect `settings.showBarText` (caller may still want an icon when false).
/// - `accountMode`: `.active` → most-constrained account; `.pinned` → matching
///   `pinnedEmail` (fall back to active if not found); `.all` → join per-account
///   fragments with " | ".
/// - `barMetric` picks the window (`.mostConstrained` uses the account's active/highest).
/// - `percentBasis`: `.remaining` shows `remainingPercent` (default), `.used` shows `usedPercent`.
/// - Optional metric label prefix (BarMetric.shortLabel) and reset countdown suffix.
/// - Severity: `.error` if the shown account has an error; `.critical` when the shown
///   window is ≥95% used (or ≤5% remaining); `.warning` when severity=="warning" or ≥85% used;
///   `.stale` when there is no data yet; else `.normal`.
public enum BarTitleFormatter {
    /// Build the single title drawn in the status item.
    public static func make(from snapshot: UsageSnapshot, settings: DisplaySettings, now: Date = Date()) -> BarTitle {
        if settings.accountMode == .all {
            return makeAll(from: snapshot, settings: settings)
        }

        guard let account = selectedAccount(from: snapshot, settings: settings) else {
            return BarTitle(text: "", severity: .stale)
        }

        let window = pickWindow(for: account, metric: settings.barMetric)
        let sev = severity(account: account, window: window)

        guard settings.showBarText else { return BarTitle(text: "", severity: sev) }

        var text = valueFragment(window: window, settings: settings)
        if settings.showResetCountdown, let window {
            let cd = DateFormatting.countdownString(to: window.resetsAt, now: now)
            if !cd.isEmpty { text += " · \(cd)" }
        }
        return BarTitle(text: text, severity: sev)
    }

    /// Pick the account the bar should represent for `.active`/`.pinned` modes.
    /// Exposed for unit testing and reuse by the popover's highlight.
    public static func selectedAccount(from snapshot: UsageSnapshot, settings: DisplaySettings) -> AccountUsage? {
        guard !snapshot.accounts.isEmpty else { return nil }

        // Errored accounts count with 0 usage unless they still carry windows.
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

    // MARK: - Private

    /// `.all` mode: one compact fragment per account joined by " | ", worst severity wins.
    private static func makeAll(from snapshot: UsageSnapshot, settings: DisplaySettings) -> BarTitle {
        guard !snapshot.accounts.isEmpty else { return BarTitle(text: "", severity: .stale) }

        var worst: BarSeverity = .normal
        var fragments: [String] = []
        for account in snapshot.accounts {
            let window = pickWindow(for: account, metric: settings.barMetric)
            worst = worseOf(worst, severity(account: account, window: window))
            fragments.append(valueFragment(window: window, settings: settings))
        }

        let text = settings.showBarText ? fragments.joined(separator: " | ") : ""
        return BarTitle(text: text, severity: worst)
    }

    /// The metric value fragment (label + number + % sign), without the countdown suffix.
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

    private static func pickWindow(for account: AccountUsage, metric: BarMetric) -> RateWindow? {
        switch metric {
        case .session: return account.session
        case .weeklyAll: return account.weeklyAll
        case .weeklyFable: return account.weeklyFable
        case .mostConstrained: return account.mostConstrainedWindow
        }
    }

    private static func severity(account: AccountUsage, window: RateWindow?) -> BarSeverity {
        if account.hasError { return .error }
        guard let window else { return .stale }
        // remaining ≤ 5 ⟺ used ≥ 95, so the critical threshold is basis-independent.
        if window.usedPercent >= 95 { return .critical }
        if window.isWarning || window.usedPercent >= 85 { return .warning }
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
