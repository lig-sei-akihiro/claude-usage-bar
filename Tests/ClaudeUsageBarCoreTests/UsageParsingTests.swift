import Foundation
import Testing
@testable import ClaudeUsageBarCore

/// 隔離されたパースのテスト: ネットワークも Keychain も使わない。固定の JSON フィクスチャを
/// `UsageAPIClient.mapLimits` に、一時ディレクトリのツリーを `ConfigDiscovery.discover` に渡す。
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
        #expect(session.resetsAt != nil)  // 小数秒付きの resets_at がパースできること

        let weeklyAll = try #require(windows.first { $0.kind == .weeklyAll })
        #expect(weeklyAll.label == "Week (all)")
        #expect(abs(weeklyAll.usedPercent - 12) < 0.0001)
        #expect(!weeklyAll.isActive)
        #expect(weeklyAll.scopeModel == nil)
        #expect(weeklyAll.resetsAt != nil)  // 小数秒なしの resets_at がパースできること

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
            // 期待どおり
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

        // `.claude.json` が無い `.claude*` ディレクトリはスキップされる。
        try fm.createDirectory(at: home.appendingPathComponent(".claude_empty"), withIntermediateDirectories: true)

        let accounts = ConfigDiscovery.discover(homeDirectory: home.path)
        let main = try #require(accounts.first { $0.folderName == "main" })
        #expect(main.configDir == mainDir.path)
        #expect(main.email == "me@example.com")
        #expect(!accounts.contains { $0.folderName == "empty" })
    }

    /// よくある構成: CLAUDE_CONFIG_DIR 未設定の default メンバーで、`oauthAccount` は
    /// ホーム直下の `~/.claude.json` にあり、`~/.claude` データディレクトリの中には
    /// `.claude.json` が無い。"No Claude Code accounts found" の回帰テスト。
    @Test func configDiscoveryReadsDefaultEmailFromHomeLevelJSON() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("cub-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        // ~/.claude データディレクトリ（中に .claude.json は無い）＋ ~/.claude.json の実際の設定。
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try #"{"oauthAccount":{"emailAddress":"solo@example.com"}}"#
            .write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        let accounts = ConfigDiscovery.discover(homeDirectory: home.path)
        let def = try #require(accounts.first { $0.folderName == "default" })
        #expect(def.configDir == home.appendingPathComponent(".claude").path)
        #expect(def.email == "solo@example.com")
    }

    /// ホーム直下にも中にも `.claude.json` が無い `~/.claude` ディレクトリは email を返さないので、
    /// `UsageService` は幻のアカウントを見せる代わりにそれを捨てる。
    @Test func configDiscoveryDefaultWithoutAnyConfigHasNoEmail() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("cub-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        try fm.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)

        let accounts = ConfigDiscovery.discover(homeDirectory: home.path)
        #expect(accounts.first { $0.folderName == "default" }?.email == nil)
    }

    @Test func retainingWindowsCarriesForwardOnTransientError() {
        let good = RateWindow(kind: .session, label: "Session (5h)", usedPercent: 40)
        let previous = UsageSnapshot(
            accounts: [AccountUsage(email: "a@x", folders: ["main"], windows: [good])],
            generatedAt: Date(timeIntervalSince1970: 100))

        // 直前まで正常だったアカウントが今エラーになっても、最後の値を保持する（error はクリア）。
        let fresh = UsageSnapshot(
            accounts: [AccountUsage(email: "a@x", folders: ["main"], error: "HTTP 429")],
            generatedAt: Date(timeIntervalSince1970: 200))
        let merged = fresh.retainingWindows(from: previous)
        #expect(merged.accounts.first?.session?.usedPercent == 40)
        #expect(merged.accounts.first?.error == nil)

        // 一度もデータが無かったアカウントは error を保持する。
        let brandNew = UsageSnapshot(
            accounts: [AccountUsage(email: "new@x", folders: ["new"], error: "HTTP 429")],
            generatedAt: Date(timeIntervalSince1970: 200))
        #expect(brandNew.retainingWindows(from: previous).accounts.first?.hasError == true)
    }
}
