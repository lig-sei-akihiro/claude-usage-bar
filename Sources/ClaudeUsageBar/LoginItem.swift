import Foundation
import ServiceManagement

/// `SMAppService` (macOS 13+) を使ってログイン時に起動するようアプリを登録する。ヘルパー
/// バンドルや entitlement は不要で、`SMAppService.mainApp` がこの .app 自身を登録する。
/// パッケージ化された (ad-hoc) 署名済みバンドルからは動作する。素の `swift run` で作った
/// 実行ファイルには登録すべきバンドルがないため、呼び出しはエラーログを出して何もしない。
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
