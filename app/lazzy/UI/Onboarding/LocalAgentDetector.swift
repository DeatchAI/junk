import Foundation

enum LocalAgentDetector {
  typealias Agent = AgentProvider
  static var agents: [Agent] { Agent.allCases }

  static func detect() -> Set<Agent> { Set(agents.filter { executable(for: $0) != nil }) }

  static func executable(for agent: Agent) -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    let executableDirectories = pathDirectories + [
      "\(home)/.grok/bin", "\(home)/.local/bin", "\(home)/.bun/bin",
      "\(home)/.amp/bin", "\(home)/.npm-global/bin",
      "/Applications/ChatGPT.app/Contents/Resources", "/Applications/Codex.app/Contents/Resources",
      "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS",
      "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS",
      "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
    ]
    if let path = ProcessInfo.processInfo.environment["DETACH_\(agent.id.uppercased())_PATH"],
      FileManager.default.isExecutableFile(atPath: path) { return path }
    let executables = [agent.executable]
    if let path = executables.flatMap({ executable in
      executableDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent(executable).path }
    }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return path }
    if agent == .opencode {
      if let bundled = Bundle.main.url(forResource: "opencode", withExtension: nil),
        FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled.path }
      let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("app/lazzy/opencode").path
      if FileManager.default.isExecutableFile(atPath: development) { return development }
    }
    return nil
  }
}
