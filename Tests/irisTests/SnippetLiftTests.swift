import Testing
import Foundation
@testable import iris

@Suite("Snippet Wrap-and-Lift Tests")
struct SnippetLiftTests {
    @Test("secret-looking keys", arguments: [
        ("API_KEY", true), ("GITHUB_TOKEN", true), ("CLIENT_SECRET", true),
        ("DB_PASSWORD", true), ("NLM_COOKIES", true), ("DATABASE_URL", false),
        ("PG_POOL_SIZE", false), ("BASE_URL", false)
    ])
    func classification(key: String, secret: Bool) {
        #expect(PluginInstaller.isSecretLooking(key: key) == secret)
    }

    @Test("classifyEnv splits secrets from config")
    func classify() {
        let lifted = PluginInstaller.classifyEnv(["API_KEY": "sk-1", "REGION": "us"])
        #expect(lifted.secrets == ["API_KEY": "sk-1"])
        #expect(lifted.config == ["REGION": "us"])
    }

    @Test("draft from a standard mcpServers snippet")
    func standardSnippet() throws {
        let snippet = """
        { "mcpServers": { "gemini-notebook-mcp": {
            "command": "notebooklm-mcp", "args": [],
            "env": { "API_KEY": "sk-live-1", "REGION": "eu" } } } }
        """
        let draft = try PluginInstaller.draft(fromSnippet: snippet)
        #expect(draft.manifest.id == "gemini-notebook-mcp")
        #expect(draft.secretValues == ["API_KEY": "sk-live-1"])
        #expect(draft.configValues == ["REGION": "eu"])
        #expect(draft.source == "snippet")

        let mcp = String(decoding: draft.files["mcp.json"]!, as: UTF8.self)
        #expect(mcp.contains("${keychain:API_KEY}"))
        #expect(mcp.contains("${config:REGION}"))
        #expect(!mcp.contains("sk-live-1"))

        // Generated manifest must re-parse and declare the lifted fields.
        let manifest = try IPFManifest.parse(
            markdown: String(decoding: draft.files["plugin.md"]!, as: UTF8.self),
            directoryName: "gemini-notebook-mcp")
        #expect(manifest.secrets?.map(\.key) == ["API_KEY"])
        #expect(manifest.config?.map(\.key) == ["REGION"])
        #expect(manifest.requires?.binaries?.first?.name == "notebooklm-mcp")
    }

    @Test("bare snippet without mcpServers wrapper also parses")
    func bareSnippet() throws {
        let draft = try PluginInstaller.draft(fromSnippet: #"{ "sqlite": { "command": "/usr/bin/sqlite-mcp", "args": ["--db", "x"] } }"#)
        #expect(draft.manifest.id == "sqlite")
        #expect(draft.secretValues.isEmpty)
    }

    @Test("invalid JSON throws")
    func invalidJSON() {
        #expect(throws: (any Error).self) {
            _ = try PluginInstaller.draft(fromSnippet: "not json")
        }
    }
}
