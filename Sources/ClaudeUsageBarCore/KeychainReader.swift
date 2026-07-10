import Foundation
import CryptoKit

/// Reads Claude Code OAuth tokens from the login Keychain.
///
/// We shell out to `/usr/bin/security` rather than calling `SecItemCopyMatching`
/// directly: a native read from an unsigned binary is not in the Keychain item's
/// ACL and would trigger a modal prompt every launch. Shelling out matches the
/// proven `claude-usage-all` approach and sidesteps the signing/entitlement work.
public enum KeychainReader {
    /// Keychain service name for a Claude Code config dir.
    ///
    /// The default `~/.claude` dir uses the bare `"Claude Code-credentials"`.
    /// Any other dir appends `sha256(absolutePath).hex[:8]`.
    ///
    /// Verified against known values: `.claude_main → e69dee50`, `.claude_sub → 9d381ca6`.
    public static func serviceName(forConfigDir dir: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir == home + "/.claude" {
            return "Claude Code-credentials"
        }
        let digest = SHA256.hash(data: Data(dir.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + String(hex.prefix(8))
    }

    /// Reads the OAuth `accessToken` for a config dir, or nil if none is stored or the
    /// item can't be parsed: shell out to `security find-generic-password -s <name> -w`,
    /// JSON-decode stdout, and return `claudeAiOauth.accessToken`.
    public static func accessToken(forConfigDir dir: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", serviceName(forConfigDir: dir), "-w"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        // Read before waiting so a large payload can't deadlock on a full pipe buffer.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }

        struct Root: Decodable {
            struct OAuth: Decodable { let accessToken: String? }
            let claudeAiOauth: OAuth?
        }
        return (try? JSONDecoder().decode(Root.self, from: data))?.claudeAiOauth?.accessToken
    }
}
