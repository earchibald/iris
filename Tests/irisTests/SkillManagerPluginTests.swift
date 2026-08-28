import Testing
import Foundation
@testable import iris

@Suite("SkillManager Plugin Integration Tests")
struct SkillManagerPluginTests {
    func tempSkillRoot(skillName: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-sm-test-\(UUID().uuidString)/skills")
        let dir = root.appendingPathComponent(skillName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: \(skillName)\ndescription: Plugin-provided skill.\n---\nBody."
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return root
    }

    @Test("listSkills includes skills from extra roots with real paths")
    func extraRoots() async throws {
        let paths = IrisPaths(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-sm-empty-\(UUID().uuidString)"))
        try paths.ensureDirectories()
        let root = try tempSkillRoot(skillName: "notebook-research")

        let skills = await SkillManager.shared.listSkills(paths: paths, extraRoots: [root])
        #expect(skills.count == 1)
        #expect(skills[0].name == "notebook-research")
        #expect(skills[0].skillFilePath == root.appendingPathComponent("notebook-research/SKILL.md").path)
    }

    @Test("discoverSkills shows the real path")
    func discoverPath() async throws {
        let paths = IrisPaths(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-sm-empty2-\(UUID().uuidString)"))
        try paths.ensureDirectories()
        let root = try tempSkillRoot(skillName: "notebook-research")

        let summary = await SkillManager.shared.discoverSkills(paths: paths, extraRoots: [root])
        #expect(summary.contains(root.appendingPathComponent("notebook-research/SKILL.md").path))
    }

    @Test("loadCustomRules appends extra rule files")
    func pluginRules() async throws {
        let paths = IrisPaths(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-sm-empty3-\(UUID().uuidString)"))
        try paths.ensureDirectories()
        let ruleFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-rule-\(UUID().uuidString).md")
        try "Plugin rule content.".write(to: ruleFile, atomically: true, encoding: .utf8)

        let rules = await SkillManager.shared.loadCustomRules(paths: paths, extraRuleFiles: [ruleFile])
        #expect(rules.contains("Plugin rule content."))
    }
}
