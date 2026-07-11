import SwiftUI
import ClaudeUsageBarCore

/// warning/critical の severity しきい値を操作する、単一トラック・2 つの thumb を持つスライダー。
///
/// トラックは 3 つの severity ゾーンで塗り分ける。`warning` までが緑、`warning` から `critical` までが
/// オレンジ、`critical` より上が赤で、共有の `SeverityColor` パレットを使うため、このコントロールは
/// メニューバーで実際に使われる色をそのまま示す。各 thumb は自分の境界をドラッグする。thumb 同士は
/// 交差できない (critical は常に warning + `gap` 以上を保つ)。値は `bounds` の範囲内の整数の使用率 (%)。
struct ThresholdSlider: View {
    @Binding var warning: Double
    @Binding var critical: Double

    private let bounds: ClosedRange<Double> = 1...99
    /// 2 つの thumb の間に保つ最小の間隔 (パーセント)。
    private let gap: Double = 1
    private let thumb: CGFloat = 18
    private let track: CGFloat = 8
    private let trackY: CGFloat = 12
    private let labelY: CGFloat = 32

    private static let space = "thresholdSlider"

    var body: some View {
        GeometryReader { geo in
            content(width: geo.size.width)
                .coordinateSpace(name: Self.space)
        }
        .frame(height: 44)
    }

    // MARK: レイアウト計算 (geometry の width が必要なので引数で渡す)

    /// `value` に対応する thumb 中心の x 座標。中心は両端の half-thumb 分のマージンの間を動くため、
    /// thumb が端で切れることはない。
    private func pos(_ value: Double, width w: CGFloat) -> CGFloat {
        let usable = max(1, w - thumb)
        let span = bounds.upperBound - bounds.lowerBound
        return thumb / 2 + CGFloat((value - bounds.lowerBound) / span) * usable
    }

    /// スライダーの座標空間内の x における値 (丸め済み・クランプなし)。
    private func value(atX x: CGFloat, width w: CGFloat) -> Double {
        let usable = max(1, w - thumb)
        let span = bounds.upperBound - bounds.lowerBound
        let t = Double((x - thumb / 2) / usable)
        return (bounds.lowerBound + t * span).rounded()
    }

    /// thumb の % ラベルがコントロールのいずれの端からもはみ出さないようにする。
    private func clampLabelX(_ x: CGFloat, width w: CGFloat) -> CGFloat {
        min(max(x, 16), w - 16)
    }

    // MARK: 部品

    @ViewBuilder
    private func content(width w: CGFloat) -> some View {
        ZStack {
            zones(width: w)
                .position(x: w / 2, y: trackY)

            thumbView
                .position(x: pos(warning, width: w), y: trackY)
                .gesture(dragForWarning(width: w))
                .accessibilityLabel("Warning threshold")
                .accessibilityValue("\(Int(warning)) percent")

            thumbView
                .position(x: pos(critical, width: w), y: trackY)
                .gesture(dragForCritical(width: w))
                .accessibilityLabel("Critical threshold")
                .accessibilityValue("\(Int(critical)) percent")

            caption("\(Int(warning))%", severity: .warning)
                .position(x: clampLabelX(pos(warning, width: w), width: w), y: labelY)
            caption("\(Int(critical))%", severity: .critical)
                .position(x: clampLabelX(pos(critical, width: w), width: w), y: labelY)
        }
    }

    /// 3 つの colour ゾーン。左から右へ重ね合わせ、角丸のトラックにクリップする。
    private func zones(width w: CGFloat) -> some View {
        let warningX = pos(warning, width: w)
        let criticalX = pos(critical, width: w)
        return ZStack(alignment: .leading) {
            Color(nsColor: SeverityColor.ns(.normal))
                .frame(width: w, height: track)
            Color(nsColor: SeverityColor.ns(.warning))
                .frame(width: max(0, criticalX - warningX), height: track)
                .offset(x: warningX)
            Color(nsColor: SeverityColor.ns(.critical))
                .frame(width: max(0, w - criticalX), height: track)
                .offset(x: criticalX)
        }
        .frame(width: w, height: track)
        .clipShape(RoundedRectangle(cornerRadius: track / 2))
    }

    private var thumbView: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
            .frame(width: thumb, height: thumb)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
            // 小さいノブでも掴みやすいように、透明の当たり判定を大きくとる。
            .frame(width: thumb + 12, height: thumb + 12)
            .contentShape(Rectangle())
    }

    private func caption(_ text: String, severity: BarSeverity) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color(nsColor: SeverityColor.ns(severity)))
    }

    // MARK: ジェスチャー

    private func dragForWarning(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { g in
                warning = min(max(value(atX: g.location.x, width: w), bounds.lowerBound), critical - gap)
            }
    }

    private func dragForCritical(width w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { g in
                critical = min(max(value(atX: g.location.x, width: w), warning + gap), bounds.upperBound)
            }
    }
}
