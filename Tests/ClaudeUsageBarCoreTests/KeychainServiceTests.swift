import Foundation
import Testing
@testable import ClaudeUsageBarCore

/// Keychain のサービス名導出を、動作実績のある `claude-usage-all` スクリプトから採取した
/// 既知の正しい値に対して固定する。これらの sha256 プレフィックスは入力パスに固有の値で、
/// テストを実行するマシンに依存しない。
struct KeychainServiceTests {
    @Test func knownServiceNames() {
        #expect(KeychainReader.serviceName(forConfigDir: "/Users/seiakihiro/.claude_main")
            == "Claude Code-credentials-e69dee50")
        #expect(KeychainReader.serviceName(forConfigDir: "/Users/seiakihiro/.claude_sub")
            == "Claude Code-credentials-9d381ca6")
    }

    @Test func bareDefaultDirUsesUnsuffixedService() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(KeychainReader.serviceName(forConfigDir: home + "/.claude") == "Claude Code-credentials")
    }
}
