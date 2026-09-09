import Foundation
import Testing
@testable import ClaudeUsageBarCore

struct TeamclaudePortTests {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("cub-tc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func writeConfig(_ contents: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func resolve(home: URL, environment: [String: String] = [:]) -> Int {
        TeamclaudeConfig.resolvePort(environment: environment, homeDirectory: home.path)
    }

    @Test func resolvePortReadsProxyPort() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeConfig(#"{"proxy":{"port":39999}}"#,
                        at: home.appendingPathComponent(".config/teamclaude.json"))
        #expect(resolve(home: home) == 39999)
    }

    @Test func resolvePortFallsBackWhenFileMissing() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(resolve(home: home) == TeamclaudeConfig.defaultPort)
    }

    @Test func resolvePortFallsBackOnMalformedJSON() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeConfig("not json at all",
                        at: home.appendingPathComponent(".config/teamclaude.json"))
        #expect(resolve(home: home) == TeamclaudeConfig.defaultPort)
    }

    @Test func resolvePortFallsBackWhenPortMissing() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeConfig(#"{"proxy":{}}"#,
                        at: home.appendingPathComponent(".config/teamclaude.json"))
        #expect(resolve(home: home) == TeamclaudeConfig.defaultPort)
    }

    @Test func resolvePortRejectsOutOfRange() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent(".config/teamclaude.json")

        try writeConfig(#"{"proxy":{"port":0}}"#, at: path)
        #expect(resolve(home: home) == TeamclaudeConfig.defaultPort)

        try writeConfig(#"{"proxy":{"port":70000}}"#, at: path)
        #expect(resolve(home: home) == TeamclaudeConfig.defaultPort)
    }

    @Test func resolvePortHonorsXDGConfigHome() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let xdg = home.appendingPathComponent("xdg")
        try writeConfig(#"{"proxy":{"port":41111}}"#,
                        at: xdg.appendingPathComponent("teamclaude.json"))
        try writeConfig(#"{"proxy":{"port":39999}}"#,
                        at: home.appendingPathComponent(".config/teamclaude.json"))
        #expect(resolve(home: home, environment: ["XDG_CONFIG_HOME": xdg.path]) == 41111)
    }

    @Test func resolvePortHonorsTeamclaudeConfig() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let explicit = home.appendingPathComponent("explicit/teamclaude.json")
        try writeConfig(#"{"proxy":{"port":42222}}"#, at: explicit)
        let xdg = home.appendingPathComponent("xdg")
        try writeConfig(#"{"proxy":{"port":41111}}"#,
                        at: xdg.appendingPathComponent("teamclaude.json"))

        let port = resolve(home: home, environment: [
            "TEAMCLAUDE_CONFIG": explicit.path,
            "XDG_CONFIG_HOME": xdg.path,
        ])
        #expect(port == 42222)
    }
}
