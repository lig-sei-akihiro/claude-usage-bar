import Foundation

/// 一連のリフレッシュ処理を統括する: 設定ディレクトリの検出 → トークンの読み取り →
/// 使用量の並行取得 → email 単位でまとめて `UsageSnapshot` を生成。
///
/// グルーピングは `claude-usage-all` と一致する: 使用量は認証単位なので、同じ email を
/// 共有する複数の設定フォルダは 1 つの `AccountUsage` にまとまる。各フォルダのトークンは
/// いずれかが取得に成功するまで順に試す。認証できないフォルダはラベルから除外される。
public struct UsageService: Sendable {
    public var client: UsageAPIClient

    public init(client: UsageAPIClient = UsageAPIClient()) {
        self.client = client
    }

    /// 検出した全アカウントにまたがるスナップショットを生成する。取得は並行して実行され、
    /// アカウント単位の失敗は例外を投げるのではなく `AccountUsage.error` になる。
    public func snapshot(now: Date = Date()) async -> UsageSnapshot {
        // 認証済みの email 単位でフォルダをグルーピングする。email を持たない設定ディレクトリ
        // (例: 素の ~/.claude)は実在のアカウントではない — スキップして、ポップオーバーに
        // "(unknown)" として現れたりメニューバーのタイトルに紛れ込んだりしないようにする。
        // 検出は configDir 順にソートされるので、グループ内のフォルダ順序は安定する。
        var groups: [String: [(folder: String, dir: String)]] = [:]
        for account in ConfigDiscovery.discover() {
            guard let email = account.email else { continue }
            groups[email, default: []].append((account.folderName, account.configDir))
        }

        let client = self.client
        return await withTaskGroup(of: AccountUsage.self) { group in
            for (email, entries) in groups {
                group.addTask {
                    // email を共有するフォルダは、それぞれ異なるトークンを持ちうる(例: 使用中の
                    // ~/.claude_main と並存する古いデフォルトの ~/.claude)。順に試して実際に取得
                    // できた最初のものを採用し、期限切れのトークン 1 つでアカウント全体が沈まない
                    // ようにする。トークンが認証できないフォルダ(欠落、401、403)はラベルから除外
                    // する — 壊れたフォルダを表示する価値はない。
                    var excluded = Set<String>()
                    var lastError = "no token"
                    var fetched: [RateWindow]?
                    for entry in entries {
                        guard let token = KeychainReader.accessToken(forConfigDir: entry.dir) else {
                            excluded.insert(entry.folder); lastError = "no token"; continue
                        }
                        do {
                            fetched = try await client.fetchWindows(token: token)
                            break
                        } catch let error as UsageAPIError {
                            lastError = error.shortMessage
                            if case .http(let code) = error, code == 401 || code == 403 {
                                excluded.insert(entry.folder)
                            }
                        } catch {
                            lastError = "error"
                        }
                    }
                    let folders = entries.map { $0.folder }.filter { !excluded.contains($0) }.sorted()
                    if let fetched {
                        return AccountUsage(email: email, folders: folders, windows: fetched, error: nil, fetchedAt: now)
                    }
                    return AccountUsage(email: email, folders: folders, error: lastError, fetchedAt: now)
                }
            }
            var accounts: [AccountUsage] = []
            for await account in group { accounts.append(account) }
            // email ではなく設定フォルダ名でソートする(例: "sub" より "main" が先)。
            accounts.sort { $0.folders.joined(separator: "/") < $1.folders.joined(separator: "/") }
            return UsageSnapshot(accounts: accounts, generatedAt: now)
        }
    }
}
