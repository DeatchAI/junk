import Darwin
import Foundation

/// Only read-only status commands run automatically. No prompts or credentials are retained.
enum AgentStatusProbe {
  static func check(_ agent: AgentProvider, executable: String, includeCursorAPIKey: Bool = true) async -> AgentReadiness {
    let arguments: [String]
    switch agent {
    case .codex: arguments = ["login", "status"]
    case .claude: arguments = ["auth", "status", "--json"]
    case .cursor: arguments = ["status"]
    case .fx: arguments = ["status", "--json"]
    default: return .installed
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detach-agent-status-\(UUID())")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      defer { try? FileManager.default.removeItem(at: directory) }
      let outputURL = directory.appendingPathComponent("status")
      FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
      let output = try FileHandle(forWritingTo: outputURL)
      defer { try? output.close() }
      let process = Process()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = output
      process.standardError = output
      var environment = ProcessInfo.processInfo.environment
      if agent == .cursor, includeCursorAPIKey, let apiKey = try? CursorProviderKeychain.read() {
        environment["CURSOR_API_KEY"] = apiKey
      }
      environment["PATH"] = ([URL(fileURLWithPath: executable).deletingLastPathComponent().path,
        "/opt/homebrew/bin", "/usr/local/bin"] + [environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
      process.environment = environment
      try process.run()
      let deadline = Date().addingTimeInterval(5)
      while process.isRunning && Date() < deadline && !Task.isCancelled { try? await Task.sleep(nanoseconds: 20_000_000) }
      if process.isRunning {
        process.terminate()
        try? await Task.sleep(nanoseconds: 100_000_000)
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        return AgentReadiness.installed
      }
      let reader = try FileHandle(forReadingFrom: outputURL)
      defer { try? reader.close() }
      let data = try reader.read(upToCount: 65_536) ?? Data()
      return AgentReadiness.parse(agent: agent, exitCode: process.terminationStatus,
        output: String(data: data, encoding: .utf8) ?? "")
    } catch { return AgentReadiness.installed }
  }
}
