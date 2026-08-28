import Foundation

/// A fully-specified pending install. Secrets ride in memory only; `commit` moves them to
/// the Keychain and never writes them into the plugin directory.
struct PluginDraft: Sendable {
    var manifest: IPFManifest
    var files: [String: Data]
    var secretValues: [String: String] = [:]
    var configValues: [String: String] = [:]
    var source: String
}

/// The one install/uninstall primitive every flow converges on. All writes are staged into a
/// temp directory and validated before anything lands in `~/.iris/plugins/` — cancel or
/// failure at any point leaves no trace.
struct PluginInstaller: Sendable {
    let paths: IrisPaths

    /// Local-directory flow: read every regular file into a draft and validate the manifest.
    func stage(directory: URL, source: String) throws -> PluginDraft {
        let fm = FileManager.default
        let manifestURL = directory.appendingPathComponent("plugin.md")
        let content = try String(contentsOf: manifestURL, encoding: .utf8)
        let manifest = try IPFManifest.parse(markdown: content, directoryName: directory.lastPathComponent)

        var files: [String: Data] = [:]
        let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        let dirPath = (directory.path as NSString).standardizingPath
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let filePath = (url.path as NSString).standardizingPath
            if filePath.hasPrefix(dirPath + "/") {
                let relative = String(filePath.dropFirst(dirPath.count + 1))
                files[relative] = try Data(contentsOf: url)
            }
        }
        return PluginDraft(manifest: manifest, files: files, source: source)
    }

    func commit(_ draft: PluginDraft) throws {
        let fm = FileManager.default
        let id = draft.manifest.id

        // Stage into a temp dir and re-validate what will actually land on disk.
        let staging = fm.temporaryDirectory.appendingPathComponent("iris-staging-\(UUID().uuidString)/\(id)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging.deletingLastPathComponent()) }

        for (relative, data) in draft.files {
            let target = staging.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        let written = try String(contentsOf: staging.appendingPathComponent("plugin.md"), encoding: .utf8)
        _ = try IPFManifest.parse(markdown: written, directoryName: id)

        // Move into place (replace an existing install of the same id).
        let destination = paths.pluginsDir.appendingPathComponent(id)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: staging, to: destination)

        // Only after the directory landed: secrets to Keychain, state to plugins.json.
        if !draft.secretValues.isEmpty {
            let service = KeychainManager.pluginService(id)
            var existing = KeychainManager.shared.secrets(service: service)
            existing.merge(draft.secretValues) { _, new in new }
            KeychainManager.shared.saveSecrets(existing, service: service)
        }
        let store = PluginStateStore(paths: paths)
        var states = store.load()
        var state = states[id] ?? PluginState()
        state.source = draft.source
        state.installedVersion = draft.manifest.version
        state.configValues.merge(draft.configValues) { _, new in new }
        states[id] = state
        store.save(states)
    }

    /// Stop the plugin's servers, delete its directory, Keychain service, and state entry.
    /// External auth credential stores (e.g. nlm's cookie directory) belong to the tool and
    /// are deliberately left alone.
    func uninstall(id: String) async throws {
        await MCPManager.shared.stopServers(withPrefix: "\(id).")
        let dir = paths.pluginsDir.appendingPathComponent(id)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        KeychainManager.shared.deleteSecrets(service: KeychainManager.pluginService(id))
        let store = PluginStateStore(paths: paths)
        var states = store.load()
        states[id] = nil
        store.save(states)
    }
}
