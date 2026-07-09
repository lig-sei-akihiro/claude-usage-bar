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
        var req = URLRequest(url: Self.usageURL)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-usage-bar", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch let error as URLError {
            throw UsageAPIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.transport("no HTTP response")
        }
        guard http.statusCode == 200 else {
            throw UsageAPIError.http(http.statusCode)
        }
        return try Self.mapLimits(data)
    }

    /// Maps the raw `/api/oauth/usage` payload into `[RateWindow]`. Factored out (and
    /// internal) so it can be unit-tested against fixtures without a network call.
    static func mapLimits(_ data: Data) throws -> [RateWindow] {
        struct Response: Decodable {
            struct Limit: Decodable {
                let kind: String?
                let percent: Double?
                let resetsAt: String?
                let severity: String?
                let isActive: Bool?
                let scope: Scope?
            }
            struct Scope: Decodable { let model: Model? }
            struct Model: Decodable { let displayName: String? }
            let limits: [Limit]?
        }

        let decoded: Response
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoded = try decoder.decode(Response.self, from: data)
        } catch {
            throw UsageAPIError.decoding(String(describing: error))
        }

        // Tolerate fractional seconds first, then fall back to plain internet date-time.
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return fractional.date(from: s) ?? plain.date(from: s)
        }

        var windows: [RateWindow] = []
        for limit in decoded.limits ?? [] {
            let scopeModel = limit.scope?.model?.displayName
            let mapped: (kind: RateWindowKind, label: String)?
            switch limit.kind {
            case "session": mapped = (.session, "Session (5h)")
            case "weekly_all": mapped = (.weeklyAll, "Week (all)")
            case "weekly_scoped": mapped = (.weeklyScoped, "Week (\(scopeModel ?? "scoped"))")
            default: mapped = nil
            }
            guard let mapped else { continue }
            windows.append(RateWindow(
                kind: mapped.kind,
                label: mapped.label,
                usedPercent: limit.percent ?? 0,
                resetsAt: parseDate(limit.resetsAt),
                severity: limit.severity,
                isActive: limit.isActive ?? false,
                scopeModel: mapped.kind == .weeklyScoped ? scopeModel : nil
            ))
        }
        return windows
    }
}
