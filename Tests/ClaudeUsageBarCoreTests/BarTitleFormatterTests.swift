import Foundation
import Testing
@testable import ClaudeUsageBarCore

/// バータイトルの組み立てを検証する: 残量と使用量の切り替え、メトリック選択、
/// warning/critical のしきい値、アイコンのみ (showBarText == false) の経路、
/// 複数アカウントの選択、`.pinned` のフォールバック、空スナップショット。
struct BarTitleFormatterTests {

    // MARK: - ヘルパー

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

    // MARK: - 残量と使用量

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

    // MARK: - メトリック選択

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

    // MARK: - しきい値

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

        // 基準 (basis) は critical 判定を変えてはならない (remaining ≤ 5 ⟺ used ≥ 95)。
        let remaining = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 97)])]),
            settings: DisplaySettings(percentBasis: .remaining))
        #expect(remaining.severity == .critical)
        #expect(remaining.text == "5h 3%")
    }

    @Test func customThresholds() {
        let settings = DisplaySettings(percentBasis: .used, warningThreshold: 70, criticalThreshold: 90)

        let normal = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 69)])]), settings: settings)
        #expect(normal.severity == .normal)

        let warning = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 70)])]), settings: settings)
        #expect(warning.severity == .warning)

        // 88% は critical しきい値が 90 なら warning だが、デフォルトの 95 なら critical になる。
        let stillWarning = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 88)])]), settings: settings)
        #expect(stillWarning.severity == .warning)

        let critical = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 90)])]), settings: settings)
        #expect(critical.severity == .critical)
    }

    @Test func windowSeverityIsBasisIndependent() {
        // ポップオーバーからも呼ばれる共通ヘルパー: 純粋な使用率で、サーバーのフラグを尊重する。
        #expect(BarTitleFormatter.windowSeverity(win(.session, used: 50), warningAt: 60, criticalAt: 80) == .normal)
        #expect(BarTitleFormatter.windowSeverity(win(.session, used: 65), warningAt: 60, criticalAt: 80) == .warning)
        #expect(BarTitleFormatter.windowSeverity(win(.session, used: 85), warningAt: 60, criticalAt: 80) == .critical)
        #expect(BarTitleFormatter.windowSeverity(win(.session, used: 5, severity: "warning"), warningAt: 60, criticalAt: 80) == .warning)
    }

    @Test func errorSeverity() {
        let out = BarTitleFormatter.make(
            from: snapshot([account("a@x", [], error: "auth expired")]),
            settings: .default)
        #expect(out.severity == .error)
    }

    // MARK: - リセットのカウントダウン

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
        // 1970 エポックから 1_000_000 秒後は 1970-01-12 13:46:40 UTC。+30 秒の丸めで
        // 13:47 になり、JST の +9h で 22:47 になる。
        let resets = Date(timeIntervalSince1970: 1_000_000)
        let out = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 40, resets: resets)])]),
            settings: DisplaySettings(percentBasis: .used, resetDisplay: .time))
        #expect(out.text == "5h 40% · 22:47")
    }

    // MARK: - showBarText == false のとき

    @Test func showBarTextFalseYieldsEmptyTextButRealSeverity() {
        let out = BarTitleFormatter.make(
            from: snapshot([account("a@x", [win(.session, used: 96)])]),
            settings: DisplaySettings(showBarText: false, percentBasis: .used))
        #expect(out.text == "")
        #expect(out.severity == .critical)
    }

    // MARK: - 複数アカウントの .active 選択

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

    // MARK: - .all モード

    @Test func allModeStacksLabelledLinesByNameAndTakesWorstSeverity() {
        // formatter がラベル順に並べ替えることを示すため、入力順をわざと逆にしている。
        let sub = account("b@x", [win(.session, used: 96)], folders: ["sub"])
        let main = account("a@x", [win(.session, used: 40)], folders: ["main"])
        let out = BarTitleFormatter.make(
            from: snapshot([sub, main]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))

        let lines = out.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 2)
        // フォルダ名順に並ぶ: "sub" より "main" が先。
        #expect(lines[0] == "main 5h 40%")
        #expect(lines[1] == "sub 5h 96%")
        #expect(out.severity == .critical)
    }

    @Test func allModeCapsAtTwoLinesByName() {
        let a = account("a@x", [win(.session, used: 10)], folders: ["a"])
        let b = account("b@x", [win(.session, used: 90)], folders: ["b"])
        let c = account("c@x", [win(.session, used: 50)], folders: ["c"])
        let out = BarTitleFormatter.make(
            from: snapshot([c, b, a]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))

        let lines = out.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.count == 2)
        // 名前順で先頭2つ。
        #expect(lines[0] == "a 5h 10%")
        #expect(lines[1] == "b 5h 90%")
    }

    @Test func allModeSingleAccountIsOneLabelledLine() {
        let a = account("solo@x", [win(.session, used: 30)], folders: ["only"])
        let out = BarTitleFormatter.make(
            from: snapshot([a]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))
        #expect(out.text == "only 5h 30%")
        #expect(!out.text.contains("\n"))
    }

    @Test func allModeDefaultOnlyAccountHasNoLabel() {
        // 単独の default アカウント (~/.claude) は値だけ表示する — "default" はノイズ。
        let a = account("solo@x", [win(.session, used: 30)], folders: ["default"])
        let out = BarTitleFormatter.make(
            from: snapshot([a]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))
        #expect(out.text == "5h 30%")
    }

    @Test func allModeDropsDefaultFromCombinedLabel() {
        // "default" が実在フォルダと email を共有する場合、実在フォルダだけ表示する。
        let a = account("me@x", [win(.session, used: 40)], folders: ["default", "main"])
        let out = BarTitleFormatter.make(
            from: snapshot([a]),
            settings: DisplaySettings(percentBasis: .used, accountMode: .all))
        #expect(out.text == "main 5h 40%")
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
        // フォルダ名順に並ぶ: "sub" より "main" が先。
        #expect(lines[0] == "main 5h 40% · 1h0m")
        #expect(lines[1] == "sub 5h 96% · 1h0m")
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

    // MARK: - .pinned モード

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

    // MARK: - 空スナップショット

    @Test func emptySnapshotIsStaleWithEmptyText() {
        let out = BarTitleFormatter.make(from: .empty, settings: .default)
        #expect(out.severity == .stale)
        #expect(out.text == "")
        #expect(BarTitleFormatter.selectedAccount(from: .empty, settings: .default) == nil)
    }
}
