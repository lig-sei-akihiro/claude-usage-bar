import Foundation

/// Composes the menu bar title from a snapshot + display settings.
///
/// This is the heart of requirements #4/#5/#6: it decides which account and which
/// window to show, whether to show remaining vs used, and the severity color.
///
/// Implemented by the Core-format agent. Contract:
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
        fatalError("unimplemented — Core-format agent")
    }

    /// Pick the account the bar should represent for `.active`/`.pinned` modes.
    /// Exposed for unit testing and reuse by the popover's highlight.
    public static func selectedAccount(from snapshot: UsageSnapshot, settings: DisplaySettings) -> AccountUsage? {
        fatalError("unimplemented — Core-format agent")
    }
}
