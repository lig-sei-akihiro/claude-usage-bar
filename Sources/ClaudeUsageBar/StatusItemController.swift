import AppKit
import Combine
import SwiftUI
import ClaudeUsageBarCore

/// Owns the `NSStatusItem`. Renders the color-coded bar title from
/// `BarTitleFormatter` (requirement #4), runs the refresh timer keyed off
/// `SettingsStore.refreshInterval`, drives `AppModel.snapshot`, and shows the
/// popover (`PopoverView`) / settings window (`SettingsView`).
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
        popover.contentViewController = NSHostingController(
            rootView: PopoverView().environmentObject(model)
        )

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
            window.title = "claude-usage-bar Settings"
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
            let snap = await UsageService().snapshot()
            model.snapshot = snap
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
        let color = tintColor(for: title.severity)

        if settings.showBarText && !title.text.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            ]
            button.attributedTitle = NSAttributedString(string: title.text, attributes: attributes)
            button.image = nil
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            let image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.33percent",
                accessibilityDescription: "Claude usage"
            ) ?? NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude usage")
            image?.isTemplate = true
            button.image = image
            // Only tint for attention states; leave normal/stale as the adaptive
            // template so the icon is always crisply visible and clickable (the way
            // back from icon-only mode is clicking it → popover → Settings).
            switch title.severity {
            case .warning, .critical, .error: button.contentTintColor = color
            case .normal, .stale: button.contentTintColor = nil
            }
        }
    }

    private func tintColor(for severity: BarSeverity) -> NSColor {
        switch severity {
        case .normal: return .labelColor
        case .warning: return .systemOrange
        case .critical: return .systemRed
        case .error: return .systemRed
        case .stale: return .tertiaryLabelColor
        }
    }
}
