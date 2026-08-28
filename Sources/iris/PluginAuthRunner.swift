import Foundation

struct PluginAuthStatus: Sendable, Equatable {
    let signedIn: Bool
    let output: String
}

/// Orchestrates `kind: external` auth declared in a plugin manifest. Iris never stores these
/// credentials — the tool owns them. `check` is a quick, direct status probe; `runSetup`
/// goes through run_command so it passes the same Vibecop/permission gate as any command.
enum PluginAuthRunner {
    static func check(_ auth: IPFManifest.AuthDeclaration, config: [String: String]) async -> PluginAuthStatus {
        guard let raw = auth.checkCommand,
              let command = try? PluginReferences.expand(raw, config: config, secrets: [:]) else {
            return PluginAuthStatus(signedIn: false, output: "No check_command declared or reference unresolvable")
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            nonisolated(unsafe) let timeout = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)

            process.terminationHandler = { p in
                timeout.cancel()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: PluginAuthStatus(
                    signedIn: p.terminationStatus == 0, output: output))
            }
            do {
                try process.run()
            } catch {
                timeout.cancel()
                continuation.resume(returning: PluginAuthStatus(
                    signedIn: false, output: "Failed to run check: \(error)"))
            }
        }
    }

    static func runSetup(_ auth: IPFManifest.AuthDeclaration, config: [String: String]) async -> String {
        guard let raw = auth.setupCommand,
              let command = try? PluginReferences.expand(raw, config: config, secrets: [:]) else {
            return "No setup_command declared or reference unresolvable"
        }
        return await ToolExecutor().execute(
            name: "run_command",
            args: ["command": .string(command)],
            useSandbox: false)
    }
}
