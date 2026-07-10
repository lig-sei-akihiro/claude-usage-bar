import AppKit

/// Pixel-art "Clawd" (the Claude Code mascot) + a mini usage gauge: a chunky body,
/// two eyes cut out as holes, two feet, and a 5-segment meter below. Used both for
/// the menu-bar status item and the popover header so they read as one identity.
///
/// Drawn **non-template** in an explicit colour. The gauge fills to the live usage
/// fraction. The body silhouette mirrors the sprite in `Scripts/gen_icon_svg.py`
/// (which drives the app icon); keep them in sync if the character changes.
enum ClawdGlyph {
    // '.' transparent · 'B' body · 'E' eye (left transparent → reads as a hole)
    private static let sprite = [
        ".BBBBBBBBBBB.",
        "BBBBBBBBBBBBB",
        "BBBEEBBBEEBBB",
        "BBBEEBBBEEBBB",
        "BBBEEBBBEEBBB",
        "BBBBBBBBBBBBB",
        "BBBBBBBBBBBBB",
        "BBBBBBBBBBBBB",
        "BBBBBBBBBBBBB",
        "..BB.....BB..",
        "..BB.....BB..",
    ]
    private static let cols = 13
    private static let rows = 11
    private static let gaugeSegments = 5

    /// Status-item image: content centred in the full menu-bar height. Drawn in a
    /// fixed light colour by the caller so it stays visible on the (sometimes
    /// ambiguously light/dark) menu bar.
    static func image(fraction: Double?, color: NSColor) -> NSImage {
        draw(fraction: fraction, color: color, canvasHeight: NSStatusBar.system.thickness, tight: false)
    }

    /// Tightly-cropped badge at a target height, for the popover header. The caller
    /// should pass an appearance-adaptive colour (the popover can be light or dark).
    static func badge(fraction: Double?, color: NSColor, height: CGFloat) -> NSImage {
        draw(fraction: fraction, color: color, canvasHeight: height, tight: true)
    }

    private static func draw(fraction: Double?, color: NSColor, canvasHeight: CGFloat, tight: Bool) -> NSImage {
        let gaugeH: CGFloat, gap: CGFloat, clawdH: CGFloat
        if tight {
            gaugeH = (canvasHeight * 0.15).rounded()
            gap = (canvasHeight * 0.10).rounded()
            clawdH = canvasHeight - gaugeH - gap
        } else {
            let pad: CGFloat = 2
            gaugeH = 3; gap = 2
            clawdH = max(8, canvasHeight - pad * 2 - gaugeH - gap)
        }
        let px = clawdH / CGFloat(rows)
        let clawdW = px * CGFloat(cols)
        let contentH = clawdH + gap + gaugeH
        let top = tight ? 0 : ((canvasHeight - contentH) / 2).rounded()

        let filled = fraction.map {
            Int((Double(gaugeSegments) * max(0, min(1, $0))).rounded())
        } ?? 0

        let image = NSImage(size: NSSize(width: ceil(clawdW), height: canvasHeight),
                            flipped: true) { _ in
            color.setFill()
            // Body (eye cells skipped → transparent holes that read as dark eyes).
            for (r, row) in sprite.enumerated() {
                for (c, ch) in row.enumerated() where ch == "B" {
                    NSBezierPath(rect: NSRect(x: CGFloat(c) * px, y: top + CGFloat(r) * px,
                                              width: px + 0.4, height: px + 0.4)).fill()
                }
            }
            // Segmented usage gauge below the body.
            let segGap = px * 0.55
            let segW = (clawdW - segGap * CGFloat(gaugeSegments - 1)) / CGFloat(gaugeSegments)
            let gaugeY = top + clawdH + gap
            for i in 0..<gaugeSegments {
                let rect = NSRect(x: CGFloat(i) * (segW + segGap), y: gaugeY,
                                  width: segW, height: gaugeH)
                let path = NSBezierPath(roundedRect: rect, xRadius: gaugeH * 0.35,
                                        yRadius: gaugeH * 0.35)
                // Lit segments are solid; empty ones are faint but distinct so the
                // fill level reads at a glance.
                (i < filled ? color : color.withAlphaComponent(0.20)).setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
