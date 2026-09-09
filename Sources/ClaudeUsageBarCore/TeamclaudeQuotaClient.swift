import Foundation

enum TeamclaudeError: Error, Sendable, Equatable {
    case transport(String)
    case badResponse
}

/// 黙って半分だけ表示しないよう、読めなかった件数を呼び出し側まで運ぶ。
struct QuotaResult: Sendable, Equatable {
    let accounts: [AccountUsage]
    let unreadable: Int
}

/// `weeklySonnet` は写さない。実測で `source` が `unified7d`、つまり Sonnet 固有ではなく
/// 共通週次の流用であり、Week (Sonnet) として見せると嘘になる。
enum TeamclaudeQuotaClient {
    // teamclaude 自身が HTTP プロキシなので、127.0.0.1 宛がシステムのプロキシ設定経由で
    // 回り込むのを断つ。2 秒で切るのはリフレッシュがバーの更新を止めないため。
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }()

    // `localhost` は teamclaude が IPv4 のみに bind していると `::1` に解決されて失敗する。
    static func quotaURL(port: Int) throws -> URL {
        guard let url = URL(string: "http://127.0.0.1:\(port)/teamclaude/quota") else {
            throw TeamclaudeError.transport("invalid port \(port)")
        }
        return url
    }

    @Sendable static func send(_ url: URL) async throws -> (Data, Int) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("claude-usage-bar", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let error as URLError {
            throw TeamclaudeError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TeamclaudeError.transport("no HTTP response")
        }
        return (data, http.statusCode)
    }

    // このエンドポイントに安定性の約束は無い。読まないキーは型に定義せず、定義する
    // フィールドは例外なく optional にして、キーの追加で decode が壊れないようにする。
    private struct Root: Decodable {
        let accounts: [Failable<Account>]?
    }

    private struct Account: Decodable {
        let name: String?
        let disabled: Bool?
        let buckets: Buckets?
    }

    private struct Buckets: Decodable {
        let fiveHour: Bucket?
        let weeklyShared: Bucket?
        let weeklyFable: Bucket?
    }

    private struct Bucket: Decodable {
        let utilization: Double?
        let resetAt: Double?
    }

    // 1 アカウントの型不一致で全アカウントが読めなくなるのを防ぐ。
    private struct Failable<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    /// `[]` は「プールにアカウント 0 件」という正当な状態なので throw しない。
    static func mapQuota(_ data: Data, now: Date) throws -> QuotaResult {
        // teamclaude のキーは既に camelCase。`.convertFromSnakeCase` を付けると全キーが取れなくなる。
        let decoded: Root
        do {
            decoded = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw TeamclaudeError.badResponse
        }
        guard let entries = decoded.accounts else { throw TeamclaudeError.badResponse }

        var accounts: [AccountUsage] = []
        var seen = Set<String>()
        var unreadable = 0
        for entry in entries {
            guard let account = entry.value else { unreadable += 1; continue }
            guard let name = account.name, !name.isEmpty else { continue }
            if account.disabled == true { continue }
            // `email` は Identifiable の id。重複させると ForEach の描画が壊れる。
            guard seen.insert(name).inserted else { unreadable += 1; continue }
            accounts.append(AccountUsage(
                email: name,
                folders: [],
                windows: windows(from: account.buckets),
                error: nil,
                fetchedAt: now))
        }
        return QuotaResult(accounts: accounts, unreadable: unreadable)
    }

    private static func windows(from buckets: Buckets?) -> [RateWindow] {
        [
            window(.session, "Session (5h)", scopeModel: nil, bucket: buckets?.fiveHour),
            window(.weeklyAll, "Week (all)", scopeModel: nil, bucket: buckets?.weeklyShared),
            window(.weeklyScoped, "Week (Fable)", scopeModel: "Fable", bucket: buckets?.weeklyFable),
        ].compactMap { $0 }
    }

    /// 未観測のバケットはウィンドウを作らない。0% は「使っていない」という嘘になる。
    private static func window(
        _ kind: RateWindowKind, _ label: String, scopeModel: String?, bucket: Bucket?
    ) -> RateWindow? {
        guard let utilization = bucket?.utilization else { return nil }
        return RateWindow(
            kind: kind,
            label: label,
            // `usedPercent` 0...100 の契約を境界の外に漏らさない。
            usedPercent: min(100, max(0, utilization * 100)),
            resetsAt: resetDate(bucket?.resetAt),
            severity: nil,
            isActive: false,
            scopeModel: scopeModel)
    }

    // ms epoch。0 以下は 1970 年を指し、リセット時刻として無効。
    private static func resetDate(_ milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
