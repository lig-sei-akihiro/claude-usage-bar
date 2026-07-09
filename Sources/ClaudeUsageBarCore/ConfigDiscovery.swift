import Foundation

/// A discovered Claude Code config folder.
public struct ConfigAccount: Sendable, Equatable {
    /// Absolute path, e.g. `/Users/me/.claude_main`.
    public var configDir: String
    /// Short name: the part after `.claude_`, or `"default"` for the bare `~/.claude`.
    public var folderName: String
    /// `oauthAccount.emailAddress` from `.claude.json`, if present.
    public var email: String?

    public init(configDir: String, folderName: String, email: String? = nil) {
        self.configDir = configDir
        self.folderName = folderName
        self.email = email
    }
}

/// Enumerates Claude Code config dirs under `$HOME`, mirroring `claude-usage-all`:
/// every `~/.claude*` dir that contains a `.claude.json` (plus the bare `~/.claude`).
public enum ConfigDiscovery {
    /// Discover config folders, sorted by path. Implemented by the Core-data agent.
    /// - Read `oauthAccount.emailAddress` from each `<dir>/.claude.json`.
    /// - `folderName` = basename with a leading `.claude_` stripped; bare `.claude` → "default".
    public static func discover(homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path) -> [ConfigAccount] {
        fatalError("unimplemented — Core-data agent")
    }
}
