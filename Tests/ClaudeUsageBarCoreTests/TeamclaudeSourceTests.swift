import Foundation
import Testing
@testable import ClaudeUsageBarCore

struct TeamclaudeSourceTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private let payload = """
    { "accounts": [
        { "name": "a@example.com", "buckets": {
            "fiveHour": { "utilization": 0.48, "resetAt": 1788945600000 },
            "weeklyShared": { "utilization": 0.39, "resetAt": 1789200000000 },
            "weeklyFable": { "utilization": 0.28, "resetAt": 1789200000000 } } }
    ] }
    """

    private func source(
        _ transport: @escaping @Sendable (URL) async throws -> (Data, Int)
    ) -> TeamclaudeUsageSource {
        TeamclaudeUsageSource(port: 39999, transport: transport)
    }

    @Test func sourceMapsSnapshotFromTransport() async throws {
        let body = Data(payload.utf8)
        let snapshot = await source { url in
            #expect(url.absoluteString == "http://127.0.0.1:39999/teamclaude/quota")
            return (body, 200)
        }.snapshot(now: now)

        #expect(snapshot.sourceError == nil)
        #expect(snapshot.accounts.count == 1)
        #expect(snapshot.accounts.first?.windows.count == 3)
        #expect(snapshot.generatedAt == now)
    }

    @Test func sourceReportsSourceErrorOnTransportFailure() async throws {
        let snapshot = await source { _ in
            throw TeamclaudeError.transport("connection refused")
        }.snapshot(now: now)

        #expect(snapshot.accounts.isEmpty)
        #expect(snapshot.sourceError == "teamclaude not reachable on port 39999")
    }

    @Test func sourceReportsVersionHintOn404() async throws {
        let snapshot = await source { _ in (Data(), 404) }.snapshot(now: now)
        #expect(snapshot.accounts.isEmpty)
        #expect(snapshot.sourceError == "teamclaude 1.1.17 or newer required")

        let other = await source { _ in (Data(), 503) }.snapshot(now: now)
        #expect(other.sourceError == "teamclaude HTTP 503")
    }

    @Test func sourceReportsSourceErrorOnUnusablePort() async throws {
        let snapshot = await TeamclaudeUsageSource(port: -1) { _ in
            Issue.record("transport must not be reached for an unusable port")
            return (Data(), 200)
        }.snapshot(now: now)

        #expect(snapshot.accounts.isEmpty)
        #expect(snapshot.sourceError == "teamclaude not reachable on port -1")
    }

    @Test func sourceReportsSourceErrorOnBadPayload() async throws {
        let snapshot = await source { _ in (Data("not json".utf8), 200) }.snapshot(now: now)
        #expect(snapshot.accounts.isEmpty)
        #expect(snapshot.sourceError == "teamclaude: bad response")
    }

    @Test func sourceReportsPartialReadAsSourceError() async throws {
        let body = Data("""
        { "accounts": [
            { "name": "a@example.com", "buckets": { "fiveHour": { "utilization": "0.48" } } },
            { "name": "b@example.com", "buckets": { "fiveHour": { "utilization": 0.2 } } }
        ] }
        """.utf8)
        let snapshot = await source { _ in (body, 200) }.snapshot(now: now)

        #expect(snapshot.accounts.count == 1)
        #expect(snapshot.sourceError == "teamclaude: 1 account unreadable")
    }
}
