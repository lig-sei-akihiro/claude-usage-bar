import AppKit
import SwiftUI
import ClaudeUsageBarCore

/// The one severity palette shared across the whole UI — the menu-bar glyph and
/// text, the popover per-account badges, and the popover usage bars — so "healthy"
/// always reads the same. A traffic-light ramp: green when normal, amber at warning,
/// red at critical/error, grey when stale. Warning is a yellow-gold amber (not a
/// red-orange) so it stays clearly distinct from the red at small sizes — a
/// red-shifted orange sat only ~25° of hue from the red and the two blurred together.
///
/// Each severity is **appearance-adaptive**: a darker, saturated value on light
/// backgrounds and a brighter one on dark backgrounds. macOS's stock `.systemGreen`
/// etc. barely shift between themes — the light green in particular sat at only
/// ~2.2:1 on white (illegibly pale), and the dark green was a muddy mid-tone. The
/// values below are the Radix Colors *step 11* ("accessible text") tokens: tuned to
/// clear WCAG AA as text against the theme's own background while staying vibrant
/// enough to read as a bar fill or the Clawd glyph. Measured contrast on the popover
/// backgrounds: light ≥ 4.5:1, dark ≥ 7:1.
enum SeverityColor {
    /// An appearance-adaptive `NSColor`. Resolves to the light or dark variant per the
    /// drawing appearance, so one token serves the light popover, the dark popover, and
    /// the (independently light-or-dark) menu bar.
    static func ns(_ severity: BarSeverity) -> NSColor {
        switch severity {
        case .normal:           return dynamic(light: 0x218358, dark: 0x3DD68C)
        case .warning:          return dynamic(light: 0xAB6400, dark: 0xFFCA16)
        case .critical, .error: return dynamic(light: 0xCE2C31, dark: 0xFF9592)
        case .stale:            return dynamic(light: 0x646464, dark: 0xB4B4B4)
        }
    }

    /// The SwiftUI flavour of the same palette; resolves per the view's colour scheme.
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
    /// Flatten a dynamic (appearance-dependent) colour to its concrete value for a
    /// specific appearance. The menu bar's light/dark state is driven by the wallpaper
    /// and can differ from the app's effective appearance, so its glyph and title must
    /// be resolved against the status button's own appearance rather than left to
    /// resolve ambiguously at draw time.
    func resolved(for appearance: NSAppearance?) -> NSColor {
        guard let appearance else { return self }
        var out = self
        appearance.performAsCurrentDrawingAppearance {
            // Go through `cgColor` (not `usingColorSpace`): it resolves *any* dynamic
            // colour — including semantic catalog colours like `labelColor`, which
            // `usingColorSpace` can refuse — to its concrete value for this appearance.
            out = NSColor(cgColor: self.cgColor) ?? self
        }
        return out
    }
}
