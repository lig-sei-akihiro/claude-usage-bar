import AppKit
import SwiftUI
import ClaudeUsageBarCore

/// The dropdown shown when the status item is clicked: one row per account with
/// session/weekly bars and reset times, plus a footer with refresh / settings / quit.
struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.snapshot.accounts.isEmpty {
                emptyState
            } else {
                // No scroll — the popover sizes to fit its content.
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

    /// Footer timestamp; the empty snapshot's `.distantPast` renders as "never".
    private static func updatedString(_ date: Date) -> String {
        if date == .distantPast { return "never" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Account card

/// One account: email + folders, then either an error or its usage windows.
private struct AccountCard: View {
    let account: AccountUsage
    let basis: PercentBasis
    let warningAt: Double
    let criticalAt: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                // Per-account Clawd: colour + gauge reflect THIS account's state.
                Image(nsImage: badge)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.email)
                        .font(.subheadline.bold())
                    // Hide the anonymous "default" folder; only show real folder names.
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
                .foregroundStyle(.red)
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

    /// Up to three windows in a stable order: session, weekly-all, weekly-Fable.
    private var windows: [RateWindow] {
        [account.session, account.weeklyAll, account.weeklyFable].compactMap { $0 }
    }

    /// Clawd for THIS account: coloured by its worst window via the shared palette
    /// (green/orange/red), gauge filled to that window's usage.
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

// MARK: - Window row

/// A single usage window: label, a fill bar, the percent, and the reset time.
private struct WindowRow: View {
    let window: RateWindow
    let basis: PercentBasis
    let warningAt: Double
    let criticalAt: Double

    var body: some View {
        let color = Self.color(for: BarTitleFormatter.windowSeverity(window, warningAt: warningAt, criticalAt: criticalAt))
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

    static func color(for severity: BarSeverity) -> Color {
        switch severity {
        case .critical, .error: return .red
        case .warning, .stale: return .orange
        case .normal: return .green
        }
    }
}

// MARK: - Usage bar

/// A horizontal fill bar; `fraction` is 0...1 of budget used.
///
/// Uses ProgressView instead of a GeometryReader-based bar: GeometryReader is greedy
/// and, inside a self-sizing popover, drives layout-recursion warnings (a documented
/// pitfall in similar menu bar apps). ProgressView sizes cleanly to the row width.
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ProgressView(value: max(0, min(1, fraction)))
            .progressViewStyle(.linear)
            .tint(color)
    }
}
