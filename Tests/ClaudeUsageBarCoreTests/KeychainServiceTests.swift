import XCTest
@testable import ClaudeUsageBarCore

/// Locks the Keychain service-name derivation against known-good values captured
/// from the working `claude-usage-all` script. These sha256 prefixes are a fixed
/// property of the input path, independent of the machine running the test.
final class KeychainServiceTests: XCTestCase {
    func testKnownServiceNames() {
        XCTAssertEqual(
            KeychainReader.serviceName(forConfigDir: "/Users/seiakihiro/.claude_main"),
            "Claude Code-credentials-e69dee50")
        XCTAssertEqual(
            KeychainReader.serviceName(forConfigDir: "/Users/seiakihiro/.claude_sub"),
            "Claude Code-credentials-9d381ca6")
    }

    func testBareDefaultDirUsesUnsuffixedService() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(
            KeychainReader.serviceName(forConfigDir: home + "/.claude"),
            "Claude Code-credentials")
    }
}
