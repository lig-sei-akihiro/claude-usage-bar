import Foundation

/// Orchestrates a full refresh: discover config dirs → read tokens → fetch usage
/// concurrently → group by email into a `UsageSnapshot`.
///
/// Grouping matches `claude-usage-all`: usage is per-authentication, so multiple
/// config folders sharing one email collapse into a single `AccountUsage`. Each
/// folder's token is tried until one fetches; folders that can't authenticate are
/// dropped from the label.
public struct UsageService: Sendable {
    public var client: UsageAPIClient

    public init(client: UsageAPIClient = UsageAPIClient()) {
        self.client = client
    }

    /// Produce a snapshot across all discovered accounts. Fetches run concurrently;
    /// per-account failures become `AccountUsage.error` rather than throwing.
    public func snapshot(now: Date = Date()) async -> UsageSnapshot {
        // Group folders by authenticated email. Config dirs without an email (e.g. a
        // bare ~/.claude) are not real accounts — skip them so they never appear as
        // "(unknown)" in the popover or feed the menu bar title.
        // Discovery is sorted by configDir, so folder order within a group is stable.
        var groups: [String: [(folder: String, dir: String)]] = [:]
        for account in ConfigDiscovery.discover() {
            guard let email = account.email else { continue }
            groups[email, default: []].append((account.folderName, account.configDir))
        }

        let client = self.client
        return await withTaskGroup(of: AccountUsage.self) { group in
            for (email, entries) in groups {
                group.addTask {
                    // Folders sharing an email may each hold a different token (e.g. a stale
                    // default ~/.claude alongside an active ~/.claude_main). Try each in turn
                    // and take the first that actually fetches, so one expired token doesn't
                    // sink the account. Folders whose token can't authenticate (missing, 401,
                    // 403) are dropped from the label — a broken folder isn't worth showing.
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
            // Sort by config-folder name (e.g. "main" before "sub"), not email.
            accounts.sort { $0.folders.joined(separator: "/") < $1.folders.joined(separator: "/") }
            return UsageSnapshot(accounts: accounts, generatedAt: now)
        }
    }
}
