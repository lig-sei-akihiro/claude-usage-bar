import Foundation

/// Errors surfaced to the UI as an account `error` string.
public enum UsageAPIError: Error, Sendable, Equatable {
    case noToken
    case http(Int)
    case transport(String)
    case decoding(String)

    public var shortMessage: String {
        switch self {
        case .noToken: return "no token"
        case .http(let code): return "HTTP \(code)"
        case .transport(let m): return m
        case .decoding: return "bad response"
        }
    }
}

/// Calls `GET https://api.anthropic.com/api/oauth/usage` with the OAuth bearer token
/// and the required `anthropic-beta: oauth-2025-04-20` header, then maps the
/// `limits[]` payload into `[RateWindow]`.
///
/// Implemented by the Core-data agent. Mapping rules (from `claude-usage-all`):
/// - `kind == "session"` → `.session`, label "Session (5h)"
/// - `kind == "weekly_all"` → `.weeklyAll`, label "Week (all)"
/// - `kind == "weekly_scoped"` → `.weeklyScoped`, label "Week (<model>)",
///   carrying `scope.model.display_name` into `scopeModel`
/// - copy `percent`→usedPercent, parse `resets_at` (UTC ISO-8601), `severity`, `is_active`
public struct UsageAPIClient: Sendable {
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let betaHeader = "oauth-2025-04-20"

    public init() {}

    /// Fetch and map the usage windows for one bearer token.
    public func fetchWindows(token: String) async throws -> [RateWindow] {
        fatalError("unimplemented — Core-data agent")
    }
}
