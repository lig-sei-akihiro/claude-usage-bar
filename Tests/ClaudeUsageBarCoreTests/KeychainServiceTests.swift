import Foundation
import Testing
@testable import ClaudeUsageBarCore

/// Locks the Keychain service-name derivation against known-good values captured
/// from the working `claude-usage-all` script. These sha256 prefixes are a fixed
/// property of the input path, independent of the machine running the test.
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
