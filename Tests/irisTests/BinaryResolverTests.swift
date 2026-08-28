import Testing
import Foundation
@testable import iris

@Suite("Binary Resolver Tests")
struct BinaryResolverTests {
    @Test("absolute path that exists resolves to itself")
    func absolute() {
        #expect(BinaryResolver.resolve(command: "/bin/ls", pinned: nil, searchDirs: []) == "/bin/ls")
    }

    @Test("bare name resolves via search dirs")
    func bareName() {
        #expect(BinaryResolver.resolve(command: "ls", pinned: nil, searchDirs: ["/nonexistent", "/bin"]) == "/bin/ls")
    }

    @Test("pinned path wins over search")
    func pinnedWins() {
        #expect(BinaryResolver.resolve(command: "ls", pinned: "/bin/ls", searchDirs: ["/usr/bin"]) == "/bin/ls")
    }

    @Test("missing binary returns nil")
    func missing() {
        #expect(BinaryResolver.resolve(command: "definitely-not-a-real-binary-xyz", pinned: nil, searchDirs: ["/bin"]) == nil)
    }

    @Test("pinned path that does not exist falls back to search")
    func badPin() {
        #expect(BinaryResolver.resolve(command: "ls", pinned: "/nope/ls", searchDirs: ["/bin"]) == "/bin/ls")
    }

    @Test("default search dirs include the common install locations")
    func defaults() {
        let dirs = BinaryResolver.defaultSearchDirs()
        #expect(dirs.contains("/opt/homebrew/bin"))
        #expect(dirs.contains("/usr/local/bin"))
        #expect(dirs.contains(("~/.local/bin" as NSString).expandingTildeInPath))
    }
}
