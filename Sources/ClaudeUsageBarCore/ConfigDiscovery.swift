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

/// Enumerates Claude Code config dirs under `$HOME`, mirroring `claude-usage-all`.
///
/// Two layouts exist:
/// - **Custom dir** (`CLAUDE_CONFIG_DIR=~/.claude_x`): config lives *inside* the dir at
///   `~/.claude_x/.claude.json`.
/// - **Default** (no `CLAUDE_CONFIG_DIR`, the common case): the `~/.claude` dir holds only
///   data and usually has *no* `.claude.json` inside — the config with `oauthAccount` is
///   the home-level `~/.claude.json`. We must read the email from there, or default-only
///   members (most people) get no account at all.
public enum ConfigDiscovery {
    /// Discover config folders, sorted by path.
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

        // Represent the default account via the `~/.claude` dir (that's what its keychain
        // service is keyed on) whenever either the dir or the home-level `~/.claude.json`
        // is present — the latter is where the default's `oauthAccount` actually lives.
        let bare = homeDirectory + "/.claude"
        var bareIsDir: ObjCBool = false
        let dirExists = fm.fileExists(atPath: bare, isDirectory: &bareIsDir) && bareIsDir.boolValue
        let homeConfigExists = fm.fileExists(atPath: homeDirectory + "/.claude.json")
        if dirExists || homeConfigExists { dirs.insert(bare) }

        return dirs.sorted().map { dir in
            ConfigAccount(configDir: dir, folderName: folderName(for: dir),
                          email: email(forConfigDir: dir, homeDirectory: homeDirectory))
        }
    }

    private static func folderName(for dir: String) -> String {
        let base = (dir as NSString).lastPathComponent
        if base == ".claude" { return "default" }
        if base.hasPrefix(".claude_") { return String(base.dropFirst(".claude_".count)) }
        return base
    }

    private static func email(forConfigDir dir: String, homeDirectory: String) -> String? {
        struct Root: Decodable {
            struct OAuth: Decodable { let emailAddress: String? }
            let oauthAccount: OAuth?
        }
        // Custom dirs keep the config inside; the default reads the home-level file first.
        var candidates = [dir + "/.claude.json"]
        if dir == homeDirectory + "/.claude" {
            candidates.insert(homeDirectory + "/.claude.json", at: 0)
        }
        for path in candidates {
            guard let data = FileManager.default.contents(atPath: path),
                  let email = (try? JSONDecoder().decode(Root.self, from: data))?.oauthAccount?.emailAddress,
                  !email.isEmpty
            else { continue }
            return email
        }
        return nil
    }
}
