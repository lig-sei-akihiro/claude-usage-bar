import Foundation

/// Orchestrates a full refresh: discover config dirs → read tokens → fetch usage
/// concurrently → group by email into a `UsageSnapshot`.
///
/// Grouping matches `claude-usage-all`: usage is per-authentication, so multiple
/// config folders sharing one email collapse into a single `AccountUsage` whose
/// `folders` lists every contributing folder name. The first folder that yields a
/// token is used to fetch.
///
/// Implemented by the Core-data agent.
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
                    let folders = entries.map { $0.folder }.sorted()
                    let token = entries.lazy.compactMap { KeychainReader.accessToken(forConfigDir: $0.dir) }.first
                    guard let token else {
                        return AccountUsage(email: email, folders: folders, error: "no token", fetchedAt: now)
                    }
                    do {
                        let windows = try await client.fetchWindows(token: token)
                        return AccountUsage(email: email, folders: folders, windows: windows, error: nil, fetchedAt: now)
                    } catch let error as UsageAPIError {
                        return AccountUsage(email: email, folders: folders, error: error.shortMessage, fetchedAt: now)
                    } catch {
                        return AccountUsage(email: email, folders: folders, error: "error", fetchedAt: now)
                    }
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
