import Foundation

public protocol UsageSource: Sendable {
    /// 失敗は例外ではなく値（`AccountUsage.error` か `UsageSnapshot.sourceError`）に落とす契約。
    func snapshot(now: Date) async -> UsageSnapshot
}

public enum UsageSourceKind: String, Sendable, CaseIterable, Codable {
    case local
    case teamclaude
}
