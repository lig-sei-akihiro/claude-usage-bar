import Foundation
import Testing
@testable import ClaudeUsageBarCore

/// Exercises the bar-title composition: remaining-vs-used, metric selection,
/// warning/critical thresholds, the icon-only (showBarText == false) path,
/// multi-account selection, `.pinned` fallback, and the empty snapshot.
struct BarTitleFormatterTests {

    // MARK: - Helpers

    private func win(
        _ kind: RateWindowKind,
        used: Double,
        resets: Date? = nil,
        severity: String? = nil,
        active: Bool = false,
        scope: String? = nil
    ) -> RateWindow {
        RateWindow(
            kind: kind,
            label: "\(kind)",
            usedPercent: used,
            resetsAt: resets,
            severity: severity,
            isActive: active,
            scopeModel: scope
        )
    }

    private func account(_ email: String, _ windows: [RateWindow], folders: [String] = ["f"], error: String? = nil) -> AccountUsage {
        AccountUsage(email: email, folders: folders, windows: windows, error: error)
    }

    private func snapshot(_ accounts: [AccountUsage]) -> UsageSnapshot {
        UsageSnapshot(accounts: accounts, generatedAt: Date())
    }

    // MARK: - Remaining vs used

    @Test func remainingVsUsed() {
        let snap = snapshot([account("a@x", [win(.session, used: 40)])])

        let remaining = BarTitleFormatter.make(
            from: snap,
            settings: DisplaySettings(percentBasis: .remaining))
        #expect(remaining.text == "5h 60%")
        #expect(remaining.severity == .normal)

        let used = BarTitleFormatter.make(
            from: snap,
            settings: DisplaySettings(percentBasis: .used))
        #expect(used.text == "5h 40%")
    }

    @Test func labelAndPercentSignToggles() {
        let snap = snapshot([account("a@x", [win(.session, used: 40)])])
        let bare = BarTitleFormatter.make(
            from: snap,
            settings: DisplaySettings(percentBasis: .used, showPercentSign: false, showMetricLabel: false))
        #expect(bare.text == "40")
    }

    // MARK: - Metric selection

    @Test func metricSelectionPicksTheRightWindow() {
        let acct = account("a@x", [
            win(.session, used: 40),
            win(.weeklyAll, used: 70),
            win(.weeklyScoped, used: 55, scope: "Fable"),
        ])
        let snap = snapshot([acct])

        let weekly = BarTitleFormatter.make(
            from: snap, settings: DisplaySettings(barMetric: .weeklyAll, percentBasis: .used))
        #expect(weekly.text == "W 70%")

        let fable = BarTitleFormatter.make(
            from: snap, settings: DisplaySettings(barMetric: .weeklyFable, percentBasis: .used))
        #expect(fable.text == "WF 55%")
    }

    @Test func mostConstrainedPrefersActiveWindow() {
        let acct = account("a@x", [
            win(.session, used: 40, active: true),
            win(.weeklyAll, used: 90),
        ])
        let snap = snapshot([acct])
        let out = BarTitleFormatter.make(
            from: snap, settings: DisplaySettings(barMetric: .mostConstrained, percentBasis: .used))
        #expect(out.text == "! 40%")
    }

    // MARK: - Thresholds

    @Test func warningThreshold() {
        let at85 = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 85)])]),
            settings: DisplaySettings(percentBasis: .used))
        #expect(at85.severity == .warning)

        let below = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 84)])]),
            settings: DisplaySettings(percentBasis: .used))
        #expect(below.severity == .normal)
    }

    @Test func warningFromSeverityString() {
        let out = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 10, severity: "warning")])]),
            settings: .default)
        #expect(out.severity == .warning)
    }

    @Test func criticalThreshold() {
        let at95 = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 95)])]),
            settings: DisplaySettings(percentBasis: .used))
        #expect(at95.severity == .critical)

        // Basis must not change the critical decision (remaining ≤ 5 ⟺ used ≥ 95).
        let remaining = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 97)])]),
            settings: DisplaySettings(percentBasis: .remaining))
        #expect(remaining.severity == .critical)
        #expect(remaining.text == "5h 3%")
    }

    @Test func errorSeverity() {
        let out = BarTitleFormatter.make(
            from: snapshot([account("a@x", [], error: "auth expired")]),
            settings: .default)
        #expect(out.severity == .error)
    }

    // MARK: - Reset countdown

    @Test func resetCountdownSuffix() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resets = now.addingTimeInterval(2 * 3600 + 12 * 60)
        let out = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 40, resets: resets)])]),
            settings: DisplaySettings(percentBasis: .used, resetDisplay: .countdown),
            now: now)
        #expect(out.text == "5h 40% · 2h12m")
    }

    @Test func resetTimeSuffixUsesJSTClock() {
        // 1_000_000s past the 1970 epoch is 1970-01-12 13:46:40 UTC; the +30s round
        // lands on 13:47, and +9h JST gives 22:47.
        let resets = Date(timeIntervalSince1970: 1_000_000)
        let out = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 40, resets: resets)])]),
            settings: DisplaySettings(percentBasis: .used, resetDisplay: .time))
        #expect(out.text == "5h 40% · 22:47")
    }

    // MARK: - showBarText == false

    @Test func showBarTextFalseYieldsEmptyTextButRealSeverity() {
        let out = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 96)])]),
            settings: DisplaySettings(showBarText: false, percentBasis: .used))
        #expect(out.text == "")
        #expect(out.severity == .critical)
    }

    // MARK: - Multi-account .active selection

    @Test func activeSelectsMostConstrainedAccount() {
        let a = account("low@x", [win(.session, used: 30)])
        let b = account("high@x", [win(.session, used: 90)])
        let snap = snapshot([a, b])

        let selected = BarTitleFormatter.selectedAccount(from: snap, settings: .default)
        #expect(selected?.email == "high@x")

        let out = BarTitleFormatter.make(from: snap, settings: DisplaySettings(percentBasis: .used))
        #expect(out.text == "5h 90%")
        #expect(out.severity == .warning)
    }

    @Test func erroredAccountCountsAsZeroWhenNoWindows() {
        let errored = account("err@x", [], error: "boom")
        let healthy = account("ok@x", [win(.session, used: 10)])
        let selected = BarTitleFormatter.selectedAccount(
            from: snapshot([errored, healthy]), settings: .default)
        #expect(selected?.email == "ok@x")
    }

    // MARK: - .all

    @Test func allModeStacksLabelledLinesWorstFirstAndTakesWorstSeverity() {
        let a = account("a@x", [win(.session, used: 40)], folders: ["main"])
        let b = account("b@x", [win(.session, used: 96)], folders: ["sub"])
        let out = BarTitleFormatter.make(
            from: snapshot([a, b]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))

        let lines = out.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 2)
        // Most-constrained account leads.
        #expect(lines[0] == "sub 5h 96%")
        #expect(lines[1] == "main 5h 40%")
        #expect(out.severity == .critical)
    }

    @Test func allModeCapsAtTwoMostConstrainedLines() {
        let a = account("a@x", [win(.session, used: 10)], folders: ["a"])
        let b = account("b@x", [win(.session, used: 90)], folders: ["b"])
        let c = account("c@x", [win(.session, used: 50)], folders: ["c"])
        let out = BarTitleFormatter.make(
            from: snapshot([a, b, c]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))

        let lines = out.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0] == "b 5h 90%")
        #expect(lines[1] == "c 5h 50%")
    }

    @Test func allModeSingleAccountIsOneLabelledLine() {
        let a = account("solo@x", [win(.session, used: 30)], folders: ["only"])
        let out = BarTitleFormatter.make(
            from: snapshot([a]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))
        #expect(out.text == "only 5h 30%")
        #expect(!out.text.contains("\n"))
    }

    @Test func allModeLabelFallsBackToEmailPrefixWhenNoFolders() {
        let a = account("nofolders@x", [win(.session, used: 20)], folders: [])
        let out = BarTitleFormatter.make(
            from: snapshot([a]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))
        #expect(out.text == "nofolders 5h 20%")
    }

    @Test func allModeAppliesResetSuffixPerLine() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resets = now.addingTimeInterval(3600)
        let a = account("a@x", [win(.session, used: 40, resets: resets)], folders: ["main"])
        let b = account("b@x", [win(.session, used: 96, resets: resets)], folders: ["sub"])
        let out = BarTitleFormatter.make(
            from: snapshot([a, b]),
            settings: DisplaySettings(percentBasis: .used, resetDisplay: .countdown, accountMode: .all),
            now: now)

        let lines = out.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "sub 5h 96% · 1h0m")
        #expect(lines[1] == "main 5h 40% · 1h0m")
    }

    @Test func allModeHonoursShowBarTextFalse() {
        let a = account("a@x", [win(.session, used: 40)], folders: ["main"])
        let b = account("b@x", [win(.session, used: 96)], folders: ["sub"])
        let out = BarTitleFormatter.make(
            from: snapshot([a, b]),
            settings: DisplaySettings(showBarText: false, percentBasis: .used, accountMode: .all))
        #expect(out.text == "")
        #expect(out.severity == .critical)
    }

    // MARK: - .pinned

    @Test func pinnedSelectsMatchingEmail() {
        let a = account("pinme@x", [win(.session, used: 20)])
        let b = account("busy@x", [win(.session, used: 99)])
        let selected = BarTitleFormatter.selectedAccount(
            from: snapshot([a, b]),
            settings: DisplaySettings(accountMode: .pinned, pinnedEmail: "pinme@x"))
        #expect(selected?.email == "pinme@x")
    }

    @Test func pinnedFallsBackToActiveWhenEmailMissing() {
        let a = account("a@x", [win(.session, used: 20)])
        let b = account("b@x", [win(.session, used: 99)])
        let selected = BarTitleFormatter.selectedAccount(
            from: snapshot([a, b]),
            settings: DisplaySettings(accountMode: .pinned, pinnedEmail: "ghost@x"))
        #expect(selected?.email == "b@x")
    }

    // MARK: - Empty snapshot

    @Test func emptySnapshotIsStaleWithEmptyText() {
        let out = BarTitleFormatter.make(from: .empty, settings: .default)
        #expect(out.severity == .stale)
        #expect(out.text == "")
        #expect(BarTitleFormatter.selectedAccount(from: .empty, settings: .default) == nil)
    }
}
