import Testing
@testable import iris

@Suite("Plugin Auth Runner Tests")
struct PluginAuthRunnerTests {
    func auth(check: String) -> IPFManifest.AuthDeclaration {
        var a = try! YAMLAuthHelper.make(kind: "external")
        a.checkCommand = check
        return a
    }

    @Test("exit 0 means signed in")
    func signedIn() async {
        let status = await PluginAuthRunner.check(auth(check: "true"), config: [:])
        #expect(status.signedIn)
    }

    @Test("non-zero exit means signed out")
    func signedOut() async {
        let status = await PluginAuthRunner.check(auth(check: "false"), config: [:])
        #expect(!status.signedIn)
    }

    @Test("config refs expand in the command")
    func configExpansion() async {
        let status = await PluginAuthRunner.check(
            auth(check: "test \"${config:PROFILE}\" = work"), config: ["PROFILE": "work"])
        #expect(status.signedIn)
    }

    @Test("large output does not deadlock the check")
    func largeOutput() async {
        let start = ContinuousClock.now
        let status = await PluginAuthRunner.check(
            auth(check: "head -c 200000 /dev/zero | tr '\\0' 'x'; exit 0"), config: [:])
        #expect(status.signedIn)
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test("missing check command reports signed out with explanation")
    func missingCommand() async {
        var a = auth(check: "true")
        a.checkCommand = nil
        let status = await PluginAuthRunner.check(a, config: [:])
        #expect(!status.signedIn)
        #expect(status.output.contains("check_command"))
    }
}

/// Test-only helper: AuthDeclaration has no memberwise init exposed for `kind` alone.
enum YAMLAuthHelper {
    static func make(kind: String) throws -> IPFManifest.AuthDeclaration {
        let m = try IPFManifest.parse(
            markdown: "---\nipf: \"1.0\"\nid: t\nname: T\nversion: 1.0.0\nauth:\n  - kind: \(kind)\n---\n",
            directoryName: "t")
        return m.auth![0]
    }
}
