import Testing
import Foundation
@testable import iris

@Suite("Harness Config Importer Tests")
struct HarnessConfigImporterTests {
    func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/harness-configs/\(name)")
    }

    @Test("parses servers out of each harness format", arguments: [
        ("claude_desktop_config.json", 2), ("cursor_mcp.json", 1), ("gemini_settings.json", 1)
    ])
    func parses(file: String, count: Int) throws {
        let servers = try HarnessConfigImporter.servers(at: fixture(file))
        #expect(servers.count == count)
    }

    @Test("parsed server carries command, args, env")
    func fields() throws {
        let servers = try HarnessConfigImporter.servers(at: fixture("claude_desktop_config.json"))
        let github = try #require(servers["github"])
        #expect(github["command"] as? String == "github-mcp")
        #expect((github["env"] as? [String: String])?["GITHUB_TOKEN"] == "ghp_abc")
    }

    @Test("snippetJSON round-trips through the wrap-and-lift pipeline")
    func roundTrip() throws {
        let servers = try HarnessConfigImporter.servers(at: fixture("claude_desktop_config.json"))
        let json = HarnessConfigImporter.snippetJSON(serverName: "github", raw: servers["github"]!)
        let draft = try PluginInstaller.draft(fromSnippet: json)
        #expect(draft.manifest.id == "github")
        #expect(draft.secretValues["GITHUB_TOKEN"] == "ghp_abc")
    }

    @Test("detect only lists configs that exist")
    func detect() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-home-\(UUID().uuidString)")
        let cursorDir = home.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: cursorDir, withIntermediateDirectories: true)
        try #"{ "mcpServers": {} }"#.write(to: cursorDir.appendingPathComponent("mcp.json"),
                                           atomically: true, encoding: .utf8)
        let detected = HarnessConfigImporter.detect(home: home)
        #expect(detected.map(\.name) == ["Cursor"])
    }

    @Test("known locations cover the major harnesses")
    func coverage() {
        let names = HarnessConfigImporter.knownLocations.map(\.name)
        for expected in ["Claude Desktop", "Claude Code", "Cursor", "Windsurf", "Gemini CLI", "VS Code Copilot"] {
            #expect(names.contains(expected))
        }
    }
}
