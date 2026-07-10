import SwiftUI
import ClaudeUsageBarCore

/// The dropdown content shown when the status item is clicked: one row per account
/// with session/weekly bars and reset times (requirement #5 — multi-account), plus a
/// footer with refresh / settings / quit.
///
/// Implemented by the App-UI agent. Reads everything from the injected `AppModel`
/// (`model.snapshot`, `model.settings`, `model.isRefreshing`) and calls
/// `model.refresh()` / `model.openSettings()` / `model.quit()`. Construct as
/// `PopoverView().environmentObject(model)`.
struct PopoverView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            if model.snapshot.accounts.isEmpty {
                emptyState
            } else {
                // No scroll — the popover sizes to fit its content.
                ForEach(model.snapshot.accounts) { account in
                    AccountCard(account: account, basis: model.settings.percentBasis)
                }
            }

            Divider()

            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            Text("Claude Code Usage")
                .font(.headline)
            Spacer()
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
        }
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
        HStack {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(account.email)
                .font(.subheadline.bold())
            if !account.folders.isEmpty {
                Text(account.folders.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    WindowRow(window: window, basis: basis)
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
}

// MARK: - Window row

/// A single usage window: label, a fill bar, the percent, and the reset time.
private struct WindowRow: View {
    let window: RateWindow
    let basis: PercentBasis

    var body: some View {
        let color = Self.color(for: Self.severity(of: window))
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

    // Severity thresholds (mirror BarTitleFormatter's contract).
    static func severity(of window: RateWindow) -> BarSeverity {
        if window.usedPercent >= 95 || window.remainingPercent <= 5 { return .critical }
        if window.isWarning || window.usedPercent >= 85 { return .warning }
        return .normal
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
private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(1, fraction))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * clamped)
            }
        }
        .frame(height: 6)
    }
}
