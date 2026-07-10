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

        // Host via a controller so the window adopts the SwiftUI content's fitting
        // size. Rebuilt each open so the account list reflects the latest snapshot.
        let hosting = NSHostingController(
            rootView: SettingsView(settings: model.settings, accounts: model.snapshot.accounts)
        )

        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
            window.contentViewController = hosting
        } else {
            window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = "claude-usage-bar Settings"
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        // Center *after* the window has taken the content's size, so it can never
        // grow off the top of the screen (macOS windows are anchored bottom-left).
        window.layoutIfNeeded()
        window.center()
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
            ) ?? NSImage(systemSymbolName: "chart.bar", accessibilityDescription: "Claude usage")
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = color
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
