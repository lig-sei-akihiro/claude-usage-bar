import AppKit

/// ピクセルアートの「Clawd」(Claude Code のマスコット) と小さな使用量ゲージ。ずんぐりした胴体、
/// 穴として切り抜いた 2 つの目、2 本の足、その下の 5 セグメントのメーターで構成する。メニューバーの
/// status item とポップオーバーのヘッダーの両方で使い、同一のアイデンティティとして読ませる。
///
/// 明示的な色で **non-template** として描画する。ゲージはリアルタイムの使用量の割合まで満たされる。
/// 胴体のシルエットは `Scripts/gen_icon_svg.py` (アプリアイコンを生成する) のスプライトと一致する。
/// キャラクターを変更する場合は両者を同期させること。
enum ClawdGlyph {
    // '.' は透明 · 'B' は胴体 · 'E' は目 (透明のまま残し → 穴として読ませる)
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

    /// status item 用の画像。コンテンツをメニューバーの全高の中央に配置する。呼び出し側が
    /// 固定の明るい色で描画するため、(ときにライト/ダークが曖昧な) メニューバー上でも視認性を保つ。
    static func image(fraction: Double?, color: NSColor) -> NSImage {
        draw(fraction: fraction, color: color, canvasHeight: NSStatusBar.system.thickness, tight: false)
    }

    /// ポップオーバーのヘッダー用に、目標の高さで余白を詰めて切り抜いたバッジ。呼び出し側は
    /// appearance に追従する色を渡すこと (ポップオーバーはライトにもダークにもなり得る)。
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
            // 胴体 (目のセルはスキップ → 透明な穴となり、暗い目として読める)。
            for (r, row) in sprite.enumerated() {
                for (c, ch) in row.enumerated() where ch == "B" {
                    NSBezierPath(rect: NSRect(x: CGFloat(c) * px, y: top + CGFloat(r) * px,
                                              width: px + 0.4, height: px + 0.4)).fill()
                }
            }
            // 胴体の下のセグメント分割された使用量ゲージ。
            let segGap = px * 0.55
            let segW = (clawdW - segGap * CGFloat(gaugeSegments - 1)) / CGFloat(gaugeSegments)
            let gaugeY = top + clawdH + gap
            for i in 0..<gaugeSegments {
                let rect = NSRect(x: CGFloat(i) * (segW + segGap), y: gaugeY,
                                  width: segW, height: gaugeH)
                let path = NSBezierPath(roundedRect: rect, xRadius: gaugeH * 0.35,
                                        yRadius: gaugeH * 0.35)
                // 点灯セグメントは塗りつぶし、空のセグメントは薄いが判別できるようにして、
                // 満たされた度合いが一目で読めるようにする。
                (i < filled ? color : color.withAlphaComponent(0.20)).setFill()
                path.fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
