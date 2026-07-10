import Foundation

/// Composes the menu bar title from a snapshot + display settings: decides which
/// account and which window to show, whether to show remaining vs used, and the
/// severity color.
///
/// Contract:
/// - Respect `settings.showBarText` (caller may still want an icon when false).
/// - `accountMode`: `.active` → most-constrained account; `.pinned` → matching
///   `pinnedEmail` (fall back to active if not found); `.all` → a multi-line title,
///   one account per line (capped at the 2 most-constrained), each line labelled.
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
            return makeAll(from: snapshot, settings: settings, now: now)
        }

        guard let account = selectedAccount(from: snapshot, settings: settings) else {
            return BarTitle(text: "", severity: .stale)
        }

        let window = pickWindow(for: account, metric: settings.barMetric)
        let sev = severity(account: account, window: window)

        guard settings.showBarText else { return BarTitle(text: "", severity: sev) }

        var text = valueFragment(window: window, settings: settings)
        if let window { text += resetSuffix(window: window, settings: settings, now: now) }
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

    /// The used fraction (0...1) the bar's gauge represents: the window picked by
    /// `barMetric` for the shown account, or the worst (max) across all in `.all`
    /// mode. `nil` when there is no usable window. Shared by the menu-bar glyph and
    /// the popover header badge so both track the same value.
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

    // MARK: - Private

    /// `.all` mode: a multi-line title, one labelled account per line, ordered by
    /// account label (e.g. "main" before "sub"), capped at 2 lines. Lines join with
    /// "\n" for the renderer to stack.
    private static func makeAll(from snapshot: UsageSnapshot, settings: DisplaySettings, now: Date) -> BarTitle {
        let lines = allLines(from: snapshot, settings: settings, now: now)
        guard !lines.isEmpty else { return BarTitle(text: "", severity: .stale) }

        // Severity spans ALL accounts, not just the (max 2) shown lines, so it tracks
        // the same set as `representativeFraction`: a hidden high-usage account still
        // colours the glyph to match the gauge fill.
        let worst = snapshot.accounts
            .map { severity(account: $0, window: pickWindow(for: $0, metric: settings.barMetric)) }
            .reduce(BarSeverity.normal, worseOf)
        let text = settings.showBarText ? lines.map(\.text).joined(separator: "\n") : ""
        return BarTitle(text: text, severity: worst)
    }

    /// The per-account lines shown in `.all` mode, each with **its own** severity
    /// (so the renderer can colour each line independently while the icon/gauge use
    /// the worst/max). Ordered by label, capped at 2. Empty for a no-account snapshot.
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
                return StackedLine(text: text, severity: severity(account: account, window: window))
            }
    }

    /// Short label identifying an account on its stacked line: the config folders,
    /// falling back to the email's local part. The anonymous `"default"` folder
    /// (bare `~/.claude`) is never shown — a lone default account gets no label.
    private static func accountLabel(_ account: AccountUsage) -> String {
        let named = account.folders.filter { $0 != "default" }
        if !named.isEmpty { return named.joined(separator: "/") }
        // No named folder. If there were no folders at all, fall back to the email's
        // local part; if the only folder was "default", show nothing.
        if account.folders.isEmpty {
            if let at = account.email.firstIndex(of: "@") { return String(account.email[..<at]) }
            return account.email
        }
        return ""
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

    /// Reset info appended to a fragment, per `settings.resetDisplay`.
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
