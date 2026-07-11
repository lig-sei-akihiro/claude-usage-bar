import Foundation
import CryptoKit

/// ログイン Keychain から Claude Code の OAuth トークンを読み取る。
///
/// `SecItemCopyMatching` を直接呼ぶのではなく `/usr/bin/security` を外部コマンドとして
/// 実行する: 署名なしバイナリからのネイティブな読み取りは Keychain アイテムの ACL に
/// 含まれておらず、起動のたびにモーダルダイアログを表示してしまう。外部コマンド化は
/// 実績のある `claude-usage-all` の方式に倣うもので、署名・entitlement の作業を回避できる。
public enum KeychainReader {
    /// Claude Code 設定ディレクトリに対応する Keychain サービス名。
    ///
    /// デフォルトの `~/.claude` ディレクトリは素の `"Claude Code-credentials"` を使う。
    /// それ以外のディレクトリは `sha256(absolutePath).hex[:8]` を付加する。
    ///
    /// 既知の値で検証済み: `.claude_main → e69dee50`、`.claude_sub → 9d381ca6`。
    public static func serviceName(forConfigDir dir: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if dir == home + "/.claude" {
            return "Claude Code-credentials"
        }
        let digest = SHA256.hash(data: Data(dir.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + String(hex.prefix(8))
    }

    /// 設定ディレクトリの OAuth `accessToken` を読み取る。保存されていない、あるいは
    /// アイテムをパースできない場合は nil を返す: `security find-generic-password -s <name> -w`
    /// を外部実行し、標準出力を JSON デコードして `claudeAiOauth.accessToken` を返す。
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
        // パイプバッファが埋まって大きなペイロードでデッドロックしないよう、待機の前に読み取る。
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
