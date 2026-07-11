import Foundation

/// 検出された Claude Code の設定フォルダ。
public struct ConfigAccount: Sendable, Equatable {
    /// 絶対パス。例: `/Users/me/.claude_main`。
    public var configDir: String
    /// 短縮名。`.claude_` 以降の部分。素の `~/.claude` の場合は `"default"`。
    public var folderName: String
    /// `.claude.json` に存在する場合の `oauthAccount.emailAddress`。
    public var email: String?

    public init(configDir: String, folderName: String, email: String? = nil) {
        self.configDir = configDir
        self.folderName = folderName
        self.email = email
    }
}

/// `$HOME` 配下の Claude Code 設定ディレクトリを列挙する。`claude-usage-all` と同じ挙動。
///
/// レイアウトは 2 種類ある:
/// - **カスタムディレクトリ** (`CLAUDE_CONFIG_DIR=~/.claude_x`): 設定はディレクトリ内部の
///   `~/.claude_x/.claude.json` に置かれる。
/// - **デフォルト** (`CLAUDE_CONFIG_DIR` なし、一般的なケース): `~/.claude` ディレクトリはデータのみを
///   保持し、通常はその内部に `.claude.json` が*存在しない* — `oauthAccount` を持つ設定は
///   ホーム直下の `~/.claude.json` にある。そこから email を読まないと、デフォルトしか使わない
///   メンバー(大多数)はアカウントがまったく得られない。
public enum ConfigDiscovery {
    /// 設定フォルダを検出し、パス順にソートする。
    /// - `folderName` = 先頭の `.claude_` を除いた basename。素の `.claude` は "default"。
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

        // デフォルトアカウントは `~/.claude` ディレクトリで表現する(Keychain サービス名の
        // キーもこのディレクトリに基づく)。ディレクトリかホーム直下の `~/.claude.json` の
        // いずれかが存在すれば対象とする — 後者がデフォルトの `oauthAccount` の実際の格納先。
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
        // カスタムディレクトリは設定を内部に持つ。デフォルトはまずホーム直下のファイルを読む。
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
