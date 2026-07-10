import Foundation

// MARK: - Usage model (contract)
//
// These value types are the shared contract between the data layer, the formatter,
// and the UI. They are intentionally free of AppKit so Core stays unit-testable.
// Mirrors the shape parsed by `claude-usage-all` from GET /api/oauth/usage `limits[]`.

/// Normalized kind of a usage window from a `limits[]` entry.
public enum RateWindowKind: String, Sendable, Codable {
    /// `kind == "session"` — the rolling 5-hour window.
    case session
    /// `kind == "weekly_all"` — the 7-day all-models window.
    case weeklyAll
    /// `kind == "weekly_scoped"` — a per-model weekly window (e.g. Fable).
    case weeklyScoped
}

/// One usage window (session / weekly) for an account.
public struct RateWindow: Sendable, Equatable, Codable {
    public var kind: RateWindowKind
    /// Human display label, e.g. "Session (5h)", "Week (all)", "Week (Fable)".
    public var label: String
    /// Utilization percent used, 0...100 (from `percent`). The API exposes utilization
    /// percent for subscription plans, not an absolute token count.
    public var usedPercent: Double
    /// `resets_at` parsed as an absolute instant (the API sends UTC ISO-8601).
    public var resetsAt: Date?
    /// `severity` — "normal" / "warning" (warning ~85%+).
    public var severity: String?
    /// `is_active` — the window currently rate-limiting the account.
    public var isActive: Bool
    /// `scope.model.display_name` for `weeklyScoped` windows (e.g. "Fable").
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

    /// Remaining budget as a percent, clamped to 0...100.
    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }

    public var isWarning: Bool { (severity ?? "").lowercased() == "warning" }
}

/// Usage for a single authenticated account (email). One email may be shared by
/// several config folders (`~/.claude_main`, `~/.claude_sub`, …) — they collapse here.
public struct AccountUsage: Sendable, Equatable, Codable, Identifiable {
    public var email: String
    /// Config-folder short names sharing this auth, e.g. ["main", "sub"].
    public var folders: [String]
    public var windows: [RateWindow]
    /// Non-nil when discovery or fetch failed (auth expired, no token, HTTP error).
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

    /// The window currently rate-limiting this account (`is_active`), else the highest-used window.
    public var mostConstrainedWindow: RateWindow? {
        if let active = windows.first(where: { $0.isActive }) { return active }
        return windows.max(by: { $0.usedPercent < $1.usedPercent })
    }

    public var hasError: Bool { error != nil }
}

/// A full snapshot across every discovered account, produced by `UsageService`.
public struct UsageSnapshot: Sendable, Equatable, Codable {
    public var accounts: [AccountUsage]
    public var generatedAt: Date

    public init(accounts: [AccountUsage], generatedAt: Date) {
        self.accounts = accounts
        self.generatedAt = generatedAt
    }

    public static let empty = UsageSnapshot(accounts: [], generatedAt: .distantPast)

    /// Carry forward last-known windows for accounts that just errored with no fresh
    /// data (e.g. a transient HTTP 429), so a blip doesn't blank the bar to "?". An
    /// account that never had data keeps its error.
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

// MARK: - Menu bar title (contract)

/// Severity that drives the menu bar title color.
public enum BarSeverity: String, Sendable, Codable {
    case normal
    case warning
    case critical
    /// Fetch/auth failed for the shown account(s).
    case error
    /// No fresh data yet / all accounts stale.
    case stale
}

/// The composed menu bar title: the text drawn in the status item plus a severity for color.
public struct BarTitle: Sendable, Equatable {
    public var text: String
    public var severity: BarSeverity

    public init(text: String, severity: BarSeverity) {
        self.text = text
        self.severity = severity
    }

    /// Placeholder shown before the first refresh completes.
    public static let placeholder = BarTitle(text: "…", severity: .stale)
}
