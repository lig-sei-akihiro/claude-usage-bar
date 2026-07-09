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
        let fm = FileManager.default
        var dirs = Set<String>()

        if let entries = try? fm.contentsOfDirectory(atPath: homeDirectory) {
            for name in entries where name.hasPrefix(".claude") {
                let path = homeDirectory + "/" + name
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                if fm.fileExists(atPath: path + "/.claude.json") { dirs.insert(path) }
            }
        }

        // The bare `~/.claude` is always a config dir when present, even without a `.claude.json`.
        let bare = homeDirectory + "/.claude"
        var bareIsDir: ObjCBool = false
        if fm.fileExists(atPath: bare, isDirectory: &bareIsDir), bareIsDir.boolValue { dirs.insert(bare) }

        return dirs.sorted().map { dir in
            ConfigAccount(configDir: dir, folderName: folderName(for: dir), email: email(inDir: dir))
        }
    }

    private static func folderName(for dir: String) -> String {
        let base = (dir as NSString).lastPathComponent
        if base == ".claude" { return "default" }
        if base.hasPrefix(".claude_") { return String(base.dropFirst(".claude_".count)) }
        return base
    }

    private static func email(inDir dir: String) -> String? {
        struct Root: Decodable {
            struct OAuth: Decodable { let emailAddress: String? }
            let oauthAccount: OAuth?
        }
        guard let data = FileManager.default.contents(atPath: dir + "/.claude.json") else { return nil }
        return (try? JSONDecoder().decode(Root.self, from: data))?.oauthAccount?.emailAddress
    }
}
