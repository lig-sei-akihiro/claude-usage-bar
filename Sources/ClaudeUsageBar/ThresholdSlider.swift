import SwiftUI
import ClaudeUsageBarCore

/// A single-track, dual-thumb slider for the warning/critical severity thresholds.
///
/// The track is painted in the three severity zones — green up to `warning`, orange
/// from `warning` to `critical`, red above `critical` — using the shared `SeverityColor`
/// palette, so the control shows exactly the colours the menu bar will use. Each thumb
/// drags its own boundary; the thumbs can't cross (critical stays ≥ warning + `gap`).
/// Values are whole used-percents in `bounds`.
struct ThresholdSlider: View {
    @Binding var warning: Double
    @Binding var critical: Double

    private let bounds: ClosedRange<Double> = 1...99
    /// Minimum separation (in percent) kept between the two thumbs.
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

    // MARK: Layout math (need the geometry width, so passed in)

    /// The x of a thumb centre for `value`. Centres travel between the two half-thumb
    /// margins so a thumb never clips off the ends.
    private func pos(_ value: Double, width w: CGFloat) -> CGFloat {
        let usable = max(1, w - thumb)
        let span = bounds.upperBound - bounds.lowerBound
        return thumb / 2 + CGFloat((value - bounds.lowerBound) / span) * usable
    }

    /// The (rounded, unclamped) value at an x in the slider's coordinate space.
    private func value(atX x: CGFloat, width w: CGFloat) -> Double {
        let usable = max(1, w - thumb)
        let span = bounds.upperBound - bounds.lowerBound
        let t = Double((x - thumb / 2) / usable)
        return (bounds.lowerBound + t * span).rounded()
    }

    /// Keep a thumb's % label from spilling past either edge of the control.
    private func clampLabelX(_ x: CGFloat, width w: CGFloat) -> CGFloat {
        min(max(x, 16), w - 16)
    }

    // MARK: Pieces

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

    /// The three colour zones, composed left-to-right and clipped to a rounded track.
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
            // Bigger invisible hit area so the small knob is easy to grab.
            .frame(width: thumb + 12, height: thumb + 12)
            .contentShape(Rectangle())
    }

    private func caption(_ text: String, severity: BarSeverity) -> some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(Color(nsColor: SeverityColor.ns(severity)))
    }

    // MARK: Gestures

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
