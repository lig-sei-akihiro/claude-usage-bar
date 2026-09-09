import Foundation

/// `GET /teamclaude/quota` 1 本で完結する。例外は投げず、失敗はすべて `sourceError` に落ちる。
public struct TeamclaudeUsageSource: UsageSource {
    private let port: Int
    private let transport: @Sendable (URL) async throws -> (Data, Int)

    public init(port: Int = TeamclaudeConfig.resolvePort()) {
        self.init(port: port, transport: TeamclaudeQuotaClient.send)
    }

    init(port: Int, transport: @escaping @Sendable (URL) async throws -> (Data, Int)) {
        self.port = port
        self.transport = transport
    }

    public func snapshot(now: Date = Date()) async -> UsageSnapshot {
        let data: Data
        do {
            let url = try TeamclaudeQuotaClient.quotaURL(port: port)
            let (body, status) = try await transport(url)
            guard status == 200 else {
                // `/teamclaude/quota` は v1.1.17 で新設。404 の原因はほぼ確実に版の古さ。
                return failure(status == 404
                    ? "teamclaude 1.1.17 or newer required"
                    : "teamclaude HTTP \(status)", now: now)
            }
            data = body
        } catch {
            return failure("teamclaude not reachable on port \(port)", now: now)
        }

        let result: QuotaResult
        do {
            result = try TeamclaudeQuotaClient.mapQuota(data, now: now)
        } catch {
            return failure("teamclaude: bad response", now: now)
        }

        guard result.unreadable > 0 else {
            return UsageSnapshot(accounts: result.accounts, generatedAt: now)
        }
        let noun = result.unreadable == 1 ? "account" : "accounts"
        return UsageSnapshot(
            accounts: result.accounts,
            generatedAt: now,
            sourceError: "teamclaude: \(result.unreadable) \(noun) unreadable")
    }

    private func failure(_ message: String, now: Date) -> UsageSnapshot {
        UsageSnapshot(accounts: [], generatedAt: now, sourceError: message)
    }
}
