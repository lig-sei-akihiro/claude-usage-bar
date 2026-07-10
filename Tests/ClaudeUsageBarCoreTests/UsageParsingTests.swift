import Foundation
import Testing
@testable import ClaudeUsageBarCore

/// Hermetic parsing tests: no network, no Keychain. Feeds fixed JSON fixtures into
/// `UsageAPIClient.mapLimits` and a temp-dir tree into `ConfigDiscovery.discover`.
struct UsageParsingTests {
    @Test func mapLimitsParsesAllKinds() throws {
        let json = """
        {
          "limits": [
            {
              "kind": "session",
              "percent": 42.5,
              "resets_at": "2026-07-09T10:30:00.000Z",
              "severity": "normal",
              "is_active": true
            },
            {
              "kind": "weekly_all",
              "percent": 12,
              "resets_at": "2026-07-14T00:00:00Z",
              "severity": "normal",
              "is_active": false
            },
            {
              "kind": "weekly_scoped",
              "percent": 88,
              "resets_at": "2026-07-14T00:00:00.500Z",
              "severity": "warning",
              "is_active": false,
              "scope": { "model": { "display_name": "Fable" } }
            }
          ]
        }
        """
        let windows = try UsageAPIClient.mapLimits(Data(json.utf8))
        #expect(windows.count == 3)

        let session = try #require(windows.first { $0.kind == .session })
        #expect(session.label == "Session (5h)")
        #expect(abs(session.usedPercent - 42.5) < 0.0001)
        #expect(session.severity == "normal")
        #expect(session.isActive)
        #expect(session.resetsAt != nil)  // fractional-seconds resets_at must parse

        let weeklyAll = try #require(windows.first { $0.kind == .weeklyAll })
        #expect(weeklyAll.label == "Week (all)")
        #expect(abs(weeklyAll.usedPercent - 12) < 0.0001)
        #expect(!weeklyAll.isActive)
        #expect(weeklyAll.scopeModel == nil)
        #expect(weeklyAll.resetsAt != nil)  // plain (no fractional) resets_at must parse

        let scoped = try #require(windows.first { $0.kind == .weeklyScoped })
        #expect(scoped.label == "Week (Fable)")
        #expect(scoped.scopeModel == "Fable")
        #expect(abs(scoped.usedPercent - 88) < 0.0001)
        #expect(scoped.severity == "warning")
        #expect(scoped.isWarning)
        #expect(scoped.resetsAt != nil)
    }

    @Test func mapLimitsIgnoresUnknownKinds() throws {
        let json = #"{ "limits": [ { "kind": "monthly_whatever", "percent": 1 } ] }"#
        let windows = try UsageAPIClient.mapLimits(Data(json.utf8))
        #expect(windows.isEmpty)
    }

    @Test func mapLimitsThrowsDecodingOnGarbage() {
        do {
            _ = try UsageAPIClient.mapLimits(Data("not json".utf8))
            Issue.record("expected mapLimits to throw")
        } catch UsageAPIError.decoding {
            // expected
        } catch {
            Issue.record("expected .decoding, got \(error)")
        }
    }

    @Test func configDiscoveryReadsEmailAndSkipsDirsWithoutConfig() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("cub-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let mainDir = home.appendingPathComponent(".claude_main")
        try fm.createDirectory(at: mainDir, withIntermediateDirectories: true)
        try #"{"oauthAccount":{"emailAddress":"me@example.com"}}"#
            .write(to: mainDir.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        // A `.claude*` dir without a `.claude.json` must be skipped.
        try fm.createDirectory(at: home.appendingPathComponent(".claude_empty"), withIntermediateDirectories: true)

        let accounts = ConfigDiscovery.discover(homeDirectory: home.path)
        let main = try #require(accounts.first { $0.folderName == "main" })
        #expect(main.configDir == mainDir.path)
        #expect(main.email == "me@example.com")
        #expect(!accounts.contains { $0.folderName == "empty" })
    }

    @Test func retainingWindowsCarriesForwardOnTransientError() {
        let good = RateWindow(kind: .session, label: "Session (5h)", usedPercent: 40)
        let previous = UsageSnapshot(
            accounts: [AccountUsage(email: "a@x", folders: ["main"], windows: [good])],
            generatedAt: Date(timeIntervalSince1970: 100))

        // A previously-good account that now errors keeps its last value (error cleared).
        let fresh = UsageSnapshot(
            accounts: [AccountUsage(email: "a@x", folders: ["main"], error: "HTTP 429")],
            generatedAt: Date(timeIntervalSince1970: 200))
        let merged = fresh.retainingWindows(from: previous)
        #expect(merged.accounts.first?.session?.usedPercent == 40)
        #expect(merged.accounts.first?.error == nil)

        // An account that never had data keeps its error.
        let brandNew = UsageSnapshot(
            accounts: [AccountUsage(email: "new@x", folders: ["new"], error: "HTTP 429")],
            generatedAt: Date(timeIntervalSince1970: 200))
        #expect(brandNew.retainingWindows(from: previous).accounts.first?.hasError == true)
    }
}
