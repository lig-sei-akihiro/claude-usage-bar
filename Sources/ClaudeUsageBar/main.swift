import AppKit

// Menu-bar-only app: `.accessory` means no Dock icon and no main window, just the
// status item. Built as an SPM executable, so we bootstrap NSApplication directly
// rather than using a SwiftUI `@main` scene.
// Top-level executable code runs on the main thread at startup, so it is safe to
// assume MainActor isolation here (AppDelegate is @MainActor).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
