import AppKit
import SwiftUI
import ClaudeUsageBarCore

/// UI 全体で共有する唯一の severity パレット。メニューバーの glyph とテキスト、ポップオーバーの
/// アカウントごとのバッジ、ポップオーバーの使用量バーで共通に使い、「健全」が常に同じ見え方に
/// なるようにする。信号機のようなグラデーション: normal は緑、warning はアンバー、critical/error は
/// 赤、stale はグレー。warning は (赤みのオレンジではなく) 黄金色のアンバーにして、小さいサイズでも
/// 赤とはっきり区別できるようにしている。赤寄りのオレンジは赤と色相が ~25° しか離れておらず、両者が
/// にじんで見分けにくかった。
///
/// 各 severity は **appearance に追従する**。ライト背景では暗めで彩度の高い値、ダーク背景では明るめの
/// 値になる。macOS 標準の `.systemGreen` などはテーマ間でほとんど変化せず、特にライトの緑は白地で
/// ~2.2:1 (判読できないほど淡い) しかなく、ダークの緑は濁った中間調だった。以下の値は Radix Colors の
/// *step 11* ("accessible text") トークンで、テーマ自身の背景に対してテキストとして WCAG AA を
/// 満たしつつ、バーの塗りや Clawd glyph として読めるだけの鮮やかさを保つよう調整されている。
/// ポップオーバー背景での実測コントラスト: ライト ≥ 4.5:1、ダーク ≥ 7:1。
enum SeverityColor {
    /// appearance に追従する `NSColor`。描画時の appearance に応じてライト/ダークいずれかの
    /// バリアントに解決されるため、1 つのトークンでライトのポップオーバー、ダークのポップオーバー、
    /// および (それらとは独立にライト/ダークが決まる) メニューバーをまかなえる。
    static func ns(_ severity: BarSeverity) -> NSColor {
        switch severity {
        case .normal:           return dynamic(light: 0x218358, dark: 0x3DD68C)
        case .warning:          return dynamic(light: 0xAB6400, dark: 0xFFCA16)
        case .critical, .error: return dynamic(light: 0xCE2C31, dark: 0xFF9592)
        case .stale:            return dynamic(light: 0x646464, dark: 0xB4B4B4)
        }
    }

    /// 同じパレットの SwiftUI 版。view の colour scheme に応じて解決される。
    static func color(_ severity: BarSeverity) -> Color {
        Color(nsColor: ns(severity))
    }

    private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

extension NSColor {
    /// 動的な (appearance に依存する) 色を、特定の appearance に対する具体的な値へと平坦化する。
    /// メニューバーのライト/ダーク状態は壁紙によって決まり、アプリの effective appearance とは異なる
    /// ことがあるため、その glyph とタイトルは描画時に曖昧に解決させるのではなく、status button 自身の
    /// appearance に対して解決しなければならない。
    func resolved(for appearance: NSAppearance?) -> NSColor {
        guard let appearance else { return self }
        var out = self
        appearance.performAsCurrentDrawingAppearance {
            // `usingColorSpace` ではなく `cgColor` を経由する。これは *あらゆる* 動的な色を、
            // (`usingColorSpace` が拒否することのある `labelColor` のようなセマンティックな
            // カタログ色も含めて) この appearance に対する具体的な値へと解決する。
            out = NSColor(cgColor: self.cgColor) ?? self
        }
        return out
    }
}
