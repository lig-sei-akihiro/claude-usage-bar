import AppKit
import ClaudeUsageBarCore

/// The one severity palette shared across the whole UI — the menu-bar glyph and
/// text, the popover per-account badges, and the popover usage bars — so "healthy"
/// always reads the same. Green-forward: green when normal, orange at warning, red
/// at critical/error, grey when stale.
enum SeverityColor {
    static func ns(_ severity: BarSeverity) -> NSColor {
        switch severity {
        case .normal: return .systemGreen
        case .warning: return .systemOrange
        case .critical, .error: return .systemRed
        case .stale: return .systemGray
        }
    }
}
