import Foundation
import ServiceManagement

/// Registers the app to launch at login via `SMAppService` (macOS 13+). No helper
/// bundle or entitlement is needed — `SMAppService.mainApp` registers this .app
/// itself. Works from a packaged, (ad-hoc) signed bundle; a bare `swift run`
/// executable has no bundle to register, so the call just no-ops with an error log.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("[ClaudeUsageBar] launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}
