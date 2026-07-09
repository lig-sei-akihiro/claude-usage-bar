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
        fatalError("unimplemented — Core-data agent")
    }
}
