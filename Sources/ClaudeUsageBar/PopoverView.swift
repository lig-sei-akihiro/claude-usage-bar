import AppKit
import SwiftUI
import ClaudeUsageBarCore

/// ステータスアイテムをクリックしたときに表示されるドロップダウン。アカウントごとに
/// 1行（セッション/週次のバーとリセット時刻）を並べ、フッターに refresh / settings / quit を置く。
struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.snapshot.accounts.isEmpty {
                emptyState
            } else {
                // スクロールしない — ポップオーバーは内容に合わせてサイズが決まる。
                ForEach(model.snapshot.accounts) { account in
                    AccountCard(account: account,
                                basis: model.settings.percentBasis,
                                warningAt: model.settings.warningThreshold,
                                criticalAt: model.settings.criticalThreshold)
                }
            }

            Divider()

            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Claude Code accounts found")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: { model.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh usage")
            }
            Text("Updated \(Self.updatedString(model.snapshot.generatedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Settings…") { model.openSettings() }
            Button("Quit") { model.quit() }
        }
    }

    /// フッターのタイムスタンプ。空スナップショットの `.distantPast` は "never" として描画される。
    private static func updatedString(_ date: Date) -> String {
        if date == .distantPast { return "never" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - アカウントカード

/// 1アカウント分: email ＋ フォルダ、続けてエラーか usage window のいずれかを表示。
private struct AccountCard: View {
    let account: AccountUsage
    let basis: PercentBasis
    let warningAt: Double
    let criticalAt: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                // このアカウント専用の Clawd: 色＋ゲージがこのアカウントの状態を反映する。
                Image(nsImage: badge)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.email)
                        .font(.subheadline.bold())
                    // 匿名の "default" フォルダは隠し、実名のフォルダだけ表示する。
                    let named = account.folders.filter { $0 != "default" }
                    if !named.isEmpty {
                        Text(named.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if account.hasError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(account.error ?? "Unavailable")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(SeverityColor.color(.error))
            } else {
                ForEach(windows, id: \.kind) { window in
                    WindowRow(window: window, basis: basis, warningAt: warningAt, criticalAt: criticalAt)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    /// 安定した順序で最大3つの window: session、weekly-all、weekly-Fable。
    private var windows: [RateWindow] {
        [account.session, account.weeklyAll, account.weeklyFable].compactMap { $0 }
    }

    /// このアカウントの Clawd: 共有パレット経由で最も逼迫した window の色（緑/アンバー/赤）で塗り、
    /// ゲージはその window の使用量まで満たす。
    private var badge: NSImage {
        ClawdGlyph.badge(fraction: fraction, color: SeverityColor.ns(severity), height: 22)
    }

    private var severity: BarSeverity {
        if account.hasError { return .error }
        guard let window = account.mostConstrainedWindow else { return .stale }
        return BarTitleFormatter.windowSeverity(window, warningAt: warningAt, criticalAt: criticalAt)
    }

    private var fraction: Double? {
        account.mostConstrainedWindow.map { $0.usedPercent / 100 }
    }
}

// MARK: - Window 行

/// 1つの usage window: ラベル、塗りバー、パーセント、リセット時刻。
private struct WindowRow: View {
    let window: RateWindow
    let basis: PercentBasis
    let warningAt: Double
    let criticalAt: Double

    var body: some View {
        let color = SeverityColor.color(BarTitleFormatter.windowSeverity(window, warningAt: warningAt, criticalAt: criticalAt))
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(window.label)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
                Text(percentText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
            }
            UsageBar(fraction: window.usedPercent / 100, color: color)
            if !resetText.isEmpty {
                Text(resetText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percentText: String {
        let value = basis == .remaining ? window.remainingPercent : window.usedPercent
        let word = basis == .remaining ? "remaining" : "used"
        return "\(Int(value.rounded()))% \(word)"
    }

    private var resetText: String {
        guard window.resetsAt != nil else { return "" }
        let jst = DateFormatting.jstResetString(window.resetsAt)
        let countdown = DateFormatting.countdownString(to: window.resetsAt)
        return countdown.isEmpty ? "resets \(jst)" : "resets \(jst) · \(countdown)"
    }
}

// MARK: - 使用量バー

/// 水平の塗りバー。`fraction` は使用済み予算の 0...1。
///
/// GeometryReader ベースのバーではなく ProgressView を使う: GeometryReader は貪欲で、
/// 自動サイズのポップオーバー内ではレイアウト再帰の警告を招く（同種のメニューバーアプリで
/// 知られた落とし穴）。ProgressView は行幅にきれいに収まる。
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ProgressView(value: max(0, min(1, fraction)))
            .progressViewStyle(.linear)
            .tint(color)
    }
}
