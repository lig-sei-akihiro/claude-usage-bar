import Foundation
import Testing
@testable import ClaudeUsageBarCore

struct TeamclaudeQuotaTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // 採取元: teamclaude v1.1.17 の GET /teamclaude/quota（メールアドレスと組織名は匿名化）。
    private let fixture = """
    {
      "accounts": [
        {
          "name": "a@example.com",
          "type": "oauth",
          "disabled": false,
          "status": "active",
          "maxUsage": null,
          "pressure": 0.42,
          "tier": { "rateLimitTier": "standard", "seatTier": "max", "weight": 5 },
          "buckets": {
            "fiveHour":     { "utilization": 0.48, "remaining": 0.99, "resetAt": 1788945600000, "source": "unified5h" },
            "weeklyShared": { "utilization": 0.39, "remaining": 0.61, "resetAt": 1789200000000, "source": "unified7d" },
            "weeklySonnet": { "utilization": 0.39, "remaining": 0.61, "resetAt": 1789200000000, "source": "unified7d" },
            "weeklyFable":  { "utilization": 0.28, "remaining": 0.72, "resetAt": 1789200000000, "source": "unified7dFable" }
          }
        },
        {
          "name": "b@example.com (Example Org)",
          "type": "oauth",
          "disabled": false,
          "status": "active",
          "buckets": {
            "fiveHour":     { "utilization": 0.10, "resetAt": 1788945600000 },
            "weeklyShared": { "utilization": 0.20, "resetAt": 1789200000000 },
            "weeklyFable":  { "utilization": 0.30, "resetAt": 1789200000000 }
          }
        }
      ],
      "aggregate": {
        "fiveHour": { "capacityWeight": 10, "usedWeight": 3.05, "remainingWeight": 6.95,
                      "utilization": 0.305, "remaining": 0.695, "knownAccounts": 2,
                      "nextResetAt": 1788945600000 }
      },
      "unknownTiers": [],
      "warmup": { "active": false },
      "defaultTarget": "a@example.com",
      "usageDimensions": ["unified5h", "unified7d"]
    }
    """

    private func map(_ json: String) throws -> QuotaResult {
        try TeamclaudeQuotaClient.mapQuota(Data(json.utf8), now: now)
    }

    private func oneAccount(buckets: String, name: String = "a@example.com") -> String {
        """
        { "accounts": [ { "name": "\(name)", "buckets": { \(buckets) } } ] }
        """
    }

    @Test func mapQuotaBuildsThreeWindows() throws {
        let result = try map(fixture)
        let account = try #require(result.accounts.first)
        #expect(account.email == "a@example.com")
        #expect(account.windows.count == 3)

        let session = try #require(account.session)
        #expect(session.label == "Session (5h)")
        #expect(abs(session.usedPercent - 48) < 0.0001)

        let weekly = try #require(account.weeklyAll)
        #expect(weekly.label == "Week (all)")
        #expect(abs(weekly.usedPercent - 39) < 0.0001)

        let fable = try #require(account.weeklyFable)
        #expect(fable.label == "Week (Fable)")
        #expect(fable.scopeModel == "Fable")
        #expect(abs(fable.usedPercent - 28) < 0.0001)
    }

    @Test func mapQuotaDropsWeeklySonnet() throws {
        let result = try map(fixture)
        for account in result.accounts {
            #expect(account.windows.count == 3)
            #expect(!account.windows.contains { $0.label.lowercased().contains("sonnet") })
        }
    }

    @Test func mapQuotaClampsOverage() throws {
        let result = try map(oneAccount(buckets: #""weeklyFable": { "utilization": 1.15 }"#))
        let fable = try #require(result.accounts.first?.weeklyFable)
        #expect(fable.usedPercent == 100)
    }

    @Test func mapQuotaSkipsMissingBuckets() throws {
        let json = oneAccount(buckets: #""weeklyShared": { "utilization": 0.2 }, "weeklyFable": { "utilization": 0.3 }"#)
        let account = try #require(try map(json).accounts.first)
        #expect(account.windows.count == 2)
        #expect(account.session == nil)
    }

    @Test func mapQuotaHandlesMissingBucketsObject() throws {
        let account = try #require(try map(#"{ "accounts": [ { "name": "a@example.com" } ] }"#).accounts.first)
        #expect(account.email == "a@example.com")
        #expect(account.windows.isEmpty)
        #expect(account.error == nil)
    }

    @Test func mapQuotaKeepsExplicitZero() throws {
        let account = try #require(try map(oneAccount(buckets: #""fiveHour": { "utilization": 0 }"#)).accounts.first)
        #expect(account.windows.count == 1)
        #expect(account.session?.usedPercent == 0)
    }

    @Test func mapQuotaSkipsNullUtilization() throws {
        let account = try #require(try map(oneAccount(buckets: #""fiveHour": { "utilization": null, "resetAt": 1788945600000 }"#)).accounts.first)
        #expect(account.windows.isEmpty)
    }

    @Test func mapQuotaParsesMsEpochResetAt() throws {
        let json = oneAccount(buckets: """
        "fiveHour": { "utilization": 0.1, "resetAt": 1788945600000 },
        "weeklyShared": { "utilization": 0.2, "resetAt": null },
        "weeklyFable": { "utilization": 0.3, "resetAt": 0 }
        """)
        let account = try #require(try map(json).accounts.first)
        #expect(account.session?.resetsAt == Date(timeIntervalSince1970: 1_788_945_600))
        #expect(account.weeklyAll?.resetsAt == nil)
        #expect(account.weeklyFable?.resetsAt == nil)
    }

    @Test func mapQuotaIgnoresRemaining() throws {
        let session = try #require(try map(fixture).accounts.first?.session)
        #expect(abs(session.remainingPercent - 52) < 0.0001)
    }

    @Test func mapQuotaDropsDisabledAccounts() throws {
        let json = """
        { "accounts": [
            { "name": "a@example.com", "disabled": true, "buckets": { "fiveHour": { "utilization": 0.1 } } },
            { "name": "b@example.com", "disabled": false, "buckets": { "fiveHour": { "utilization": 0.2 } } }
        ] }
        """
        let result = try map(json)
        #expect(result.accounts.map(\.email) == ["b@example.com"])
        #expect(result.unreadable == 0)
    }

    @Test func mapQuotaSkipsAccountsWithoutName() throws {
        let json = """
        { "accounts": [
            { "buckets": { "fiveHour": { "utilization": 0.1 } } },
            { "name": "", "buckets": { "fiveHour": { "utilization": 0.1 } } },
            { "name": "b@example.com", "buckets": { "fiveHour": { "utilization": 0.2 } } }
        ] }
        """
        let result = try map(json)
        #expect(result.accounts.map(\.email) == ["b@example.com"])
        #expect(result.unreadable == 0)
    }

    @Test func mapQuotaFoldersAreEmptyAndNoError() throws {
        let result = try map(fixture)
        for account in result.accounts {
            #expect(account.folders.isEmpty)
            #expect(account.error == nil)
            #expect(account.fetchedAt == now)
            for window in account.windows {
                #expect(!window.isActive)
                #expect(window.severity == nil)
            }
        }
    }

    @Test func mapQuotaPreservesAccountOrder() throws {
        let result = try map(fixture)
        #expect(result.accounts.map(\.email) == ["a@example.com", "b@example.com (Example Org)"])
    }

    @Test func mapQuotaIgnoresUnknownKeys() throws {
        let result = try map(fixture)
        #expect(result.accounts.count == 2)
        #expect(result.unreadable == 0)
    }

    @Test func mapQuotaSurvivesOneMalformedAccount() throws {
        let json = """
        { "accounts": [
            { "name": "a@example.com", "buckets": { "fiveHour": { "utilization": "0.48" } } },
            { "name": "b@example.com", "buckets": { "fiveHour": { "utilization": 0.2 } } }
        ] }
        """
        let result = try map(json)
        #expect(result.accounts.map(\.email) == ["b@example.com"])
        #expect(result.unreadable == 1)
    }

    @Test func mapQuotaCountsDuplicateNamesAsUnreadable() throws {
        let json = """
        { "accounts": [
            { "name": "a@example.com", "buckets": { "fiveHour": { "utilization": 0.1 } } },
            { "name": "a@example.com", "buckets": { "fiveHour": { "utilization": 0.9 } } }
        ] }
        """
        let result = try map(json)
        #expect(result.accounts.count == 1)
        #expect(abs((result.accounts.first?.session?.usedPercent ?? 0) - 10) < 0.0001)
        #expect(result.unreadable == 1)
    }

    @Test func mapQuotaThrowsWhenAccountsKeyMissing() {
        #expect(throws: TeamclaudeError.badResponse) {
            try map(#"{ "aggregate": {}, "warmup": { "active": false } }"#)
        }
    }

    @Test func mapQuotaAcceptsEmptyAccountsArray() throws {
        let result = try map(#"{ "accounts": [] }"#)
        #expect(result.accounts.isEmpty)
        #expect(result.unreadable == 0)
    }

    @Test func mapQuotaThrowsDecodingOnGarbage() {
        #expect(throws: TeamclaudeError.badResponse) {
            try map("not json")
        }
    }
}
