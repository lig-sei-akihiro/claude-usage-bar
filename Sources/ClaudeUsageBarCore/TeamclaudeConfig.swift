import Foundation

/// 設定ファイルには平文の OAuth トークンと proxy の apiKey が同居している。そのため `proxy.port`
/// 以外を型に定義せず、失敗の内容もどこにも出さずに既定ポートへ黙ってフォールバックする。
public enum TeamclaudeConfig {
    public static let defaultPort = 3456

    public static func resolvePort(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> Int {
        struct Root: Decodable {
            struct Proxy: Decodable { let port: Int? }
            let proxy: Proxy?
        }

        let path: String
        if let explicit = environment["TEAMCLAUDE_CONFIG"], !explicit.isEmpty {
            path = explicit
        } else if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            path = xdg + "/teamclaude.json"
        } else {
            path = homeDirectory + "/.config/teamclaude.json"
        }

        guard let data = FileManager.default.contents(atPath: path),
              let port = (try? JSONDecoder().decode(Root.self, from: data))?.proxy?.port,
              (1...65535).contains(port)
        else { return defaultPort }
        return port
    }
}
