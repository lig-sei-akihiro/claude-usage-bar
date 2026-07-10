import AppKit
import Combine
import SwiftUI
import ClaudeUsageBarCore

/// Owns the `NSStatusItem`. Renders the colour-coded bar title from `BarTitleFormatter`,
/// runs the refresh timer keyed off `SettingsStore.refreshInterval`, drives
/// `AppModel.snapshot`, and shows the popover / settings window.
@MainActor
final class StatusItemController {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var settingsWindow: NSWindow?
    private var refreshTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var isRefreshing = false

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        self.popover = NSPopover()
        popover.behavior = .transient
        // Canonical fix for the NSPopover "contentSize trap": NSPopover defaults to
        // 320x320 and silently clips taller SwiftUI content. sizingOptions =
        // .preferredContentSize makes the hosting controller report the SwiftUI ideal
        // size, so the popover auto-sizes to fit (no clip, no scroll needed).
        let hosting = NSHostingController(rootView: PopoverView().environmentObject(model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        model.refreshAction = { [weak self] in self?.refresh() }
        model.openSettingsAction = { [weak self] in self?.openSettings() }
        model.quitAction = { NSApp.terminate(nil) }

        // Re-render the title and reschedule the timer when display/refresh options change.
        settingsCancellable = model.settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateBar()
                self?.scheduleTimer()
            }

        updateBar()
        scheduleTimer()
    }

    // MARK: Popover

    /// Left-click toggles the popover (primary UI); right-click shows a plain
    /// menu so Settings/Quit are reachable even if the popover is unavailable.
    @objc private func handleClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshFromMenu() { model.refresh() }
    @objc private func openSettingsFromMenu() { model.openSettings() }
    @objc private func quitFromMenu() { model.quit() }

    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: Settings window

    private func openSettings() {
        popover.performClose(nil)

        // Fixed-size window. `sizingOptions = []` stops the hosting view from resizing
        // the window to the SwiftUI content — which previously either grew it off the
        // top of the screen or collapsed it to an empty pane. The content fills the
        // fixed frame and the grouped Form scrolls if it is taller.
        let hostingView = NSHostingView(
            rootView: SettingsView(settings: model.settings, accounts: model.snapshot.accounts)
        )
        hostingView.sizingOptions = []

        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            // No visible title — the form has its own icon + name header, so the window
            // title text is redundant. Keep the standard title bar (traffic lights / drag),
            // just hide the text. (`title` is still set for the Window menu / accessibility.)
            window.title = "Settings"
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            // Follow the user across Spaces: reopening brings the window to the active
            // desktop instead of switching back to the Space it first appeared on.
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.center()
            settingsWindow = window
        }
        window.contentView = hostingView

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Refresh

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        model.isRefreshing = true
        Task { @MainActor in
            let fresh = await UsageService().snapshot()
            // Keep the last-known value for any account that just transiently errored.
            model.snapshot = fresh.retainingWindows(from: model.snapshot)
            model.isRefreshing = false
            isRefreshing = false
            updateBar()
        }
    }

    // MARK: Timer

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        let seconds = model.settings.refreshInterval.rawValue
        guard seconds > 0 else { return }

        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: Bar title

    private func updateBar() {
        guard let button = statusItem.button else { return }

        let settings = model.settings.displaySettings
        let title = BarTitleFormatter.make(from: model.snapshot, settings: settings)

        // The menu bar's light/dark state follows the wallpaper, not the app's
        // appearance, so resolve the severity palette against the status button's own
        // appearance — otherwise the adaptive colours would pick the wrong variant.
        let appearance = button.effectiveAppearance

        // Clawd (the mascot) + a mini usage gauge always lead the status item, echoing
        // the app icon. Coloured by the (worst) severity from the shared palette; the
        // gauge fills to live usage.
        let glyph = ClawdGlyph.image(
            fraction: BarTitleFormatter.representativeFraction(from: model.snapshot, settings: settings),
            color: SeverityColor.ns(title.severity).resolved(for: appearance))
        button.contentTintColor = nil

        if settings.showBarText && !title.text.isEmpty {
            if title.text.contains("\n") {
                // Stacked lines: draw the glyph + both lines into one image sized to
                // the menu bar height. A raw multi-line attributedTitle left dead space
                // at the bottom; drawing our own image removes it and lets the font grow.
                // Each line's percentage is coloured by ITS OWN severity.
                let lines = BarTitleFormatter.allLines(from: model.snapshot, settings: settings)
                button.attributedTitle = NSAttributedString(string: "")
                button.image = Self.stackedTitleImage(lines: lines, leadingGlyph: glyph, appearance: appearance)
                button.imagePosition = .imageOnly
            } else {
                button.image = glyph
                button.imagePosition = .imageLeading
                button.attributedTitle = Self.barLine(
                    title.text, severity: title.severity,
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                    appearance: appearance)
            }
        } else {
            // Icon-only mode: Clawd + gauge is the whole status item.
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
            button.image = glyph
        }
    }

    /// An attributed status-bar line: the base text is the primary label colour; only
    /// the percentage token takes the severity colour (green → amber → red). The
    /// account/metric label and the reset time stay in the label colour.
    ///
    /// Both colours are resolved against `appearance` — the *status bar's* own
    /// appearance, which the caller passes from the status button. The menu bar's
    /// light/dark state is set by the wallpaper and can differ from the system theme,
    /// so left to resolve at draw time `labelColor` would follow the theme and could
    /// end up dark-on-dark (or light-on-light) against the actual menu-bar background.
    static func barLine(_ text: String, severity: BarSeverity, font: NSFont,
                        paragraph: NSParagraphStyle? = nil,
                        appearance: NSAppearance? = nil) -> NSAttributedString {
        let baseColor = NSColor.labelColor.resolved(for: appearance)
        var base: [NSAttributedString.Key: Any] = [.foregroundColor: baseColor, .font: font]
        if let paragraph { base[.paragraphStyle] = paragraph }
        let attr = NSMutableAttributedString(string: text, attributes: base)
        if let range = percentRange(in: text) {
            let color = SeverityColor.ns(severity).resolved(for: appearance)
            attr.addAttribute(.foregroundColor, value: color, range: range)
        }
        return attr
    }

    /// Range of the "NN%" (or "NN") percentage token: the trailing digit-run of the
    /// line's *head* (everything before the " · " reset). The value is always the last
    /// token of the head, so this never lands on digits inside a numeric account label
    /// (e.g. the "2" in "v2 30%") in `.all` mode, nor on the reset-time digits.
    private static func percentRange(in text: String) -> NSRange? {
        let ns = text as NSString
        let sep = ns.range(of: " · ")
        let head = sep.location == NSNotFound ? text : ns.substring(to: sep.location)
        guard let re = try? NSRegularExpression(pattern: #"\d+%?$"#) else { return nil }
        return re.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length))?.range
    }

    /// Draw an optional leading glyph plus stacked lines into an image sized to the
    /// menu bar height, vertically centered. Each line's percentage keeps its own
    /// severity colour; the layout is a single multi-line draw so spacing is stable.
    private static func stackedTitleImage(lines: [StackedLine],
                                          leadingGlyph: NSImage? = nil,
                                          appearance: NSAppearance? = nil) -> NSImage {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineSpacing = 0
        paragraph.maximumLineHeight = 10.5
        paragraph.minimumLineHeight = 10.5
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let attr = NSMutableAttributedString()
        for (i, line) in lines.enumerated() {
            if i > 0 { attr.append(NSAttributedString(string: "\n")) }
            attr.append(barLine(line.text, severity: line.severity, font: font, paragraph: paragraph, appearance: appearance))
        }
        let textSize = attr.size()
        let height = NSStatusBar.system.thickness
        let glyphW = leadingGlyph?.size.width ?? 0
        let gap: CGFloat = leadingGlyph == nil ? 0 : 4
        let textW = ceil(textSize.width)
        let width = max(1, glyphW + gap + textW + 2)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        if let glyph = leadingGlyph {
            let gy = ((height - glyph.size.height) / 2).rounded()
            glyph.draw(at: NSPoint(x: 0, y: gy), from: .zero, operation: .sourceOver, fraction: 1)
        }
        // Nudge 1pt down: each line box carries empty descender space at its bottom, so a
        // geometric center leaves the glyph mass looking slightly high. Verified visually.
        let y = ((height - textSize.height) / 2).rounded() - 1
        attr.draw(in: NSRect(x: glyphW + gap, y: y, width: textW, height: ceil(textSize.height)))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

}
