import Foundation

public struct UsageService: Sendable {
    private let source: any UsageSource

    public init(_ kind: UsageSourceKind = .local, client: UsageAPIClient = UsageAPIClient()) {
        switch kind {
        case .local: self.source = LocalConfigUsageSource(client: client)
        case .teamclaude: self.source = TeamclaudeUsageSource()
        }
    }

    public init(source: any UsageSource) {
        self.source = source
    }

    public func snapshot(now: Date = Date()) async -> UsageSnapshot {
        await source.snapshot(now: now)
    }
}
