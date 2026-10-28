import Foundation

@main
struct ProviderCatalogTests {
  static func main() throws {
    let defaults = UserDefaults.standard
    let selectionKey = "detach_selected_agent"
    let priorSelection = defaults.object(forKey: selectionKey)
    defer {
      if let priorSelection { defaults.set(priorSelection, forKey: selectionKey) }
      else { defaults.removeObject(forKey: selectionKey) }
    }
    defaults.set("hosted", forKey: selectionKey)
    assert(DetachSettings.selectedAgent == "codex")
    assert(defaults.string(forKey: selectionKey) == "codex", "Retired selection must migrate in storage too")
    defaults.set("opencode", forKey: selectionKey)
    assert(DetachSettings.selectedAgent == "opencode", "User-owned OpenCode must remain selected")
    let assets = URL(fileURLWithPath: CommandLine.arguments[1])
    assert(AgentProvider.allCases.count == 8)
    assert(Set(AgentProvider.allCases.map(\.id)).count == 8)
    assert(AgentProvider(rawValue: "hosted") == nil)
    for provider in [AgentProvider.pi, .amp, .omp] {
      assert(LocalAgentDetector.agents.contains(provider))
      assert(AgentProvider.identifier(for: provider.name) == provider.id)
      assert(AgentProvider.displayName(for: provider.id) == provider.name)
      assert(!provider.subtitle(isInstalled: false).isEmpty)
      let svg = assets.appendingPathComponent(provider.asset + ".imageset/logo.svg")
      let contents = try String(contentsOf: svg, encoding: .utf8)
      assert(contents.contains("<path"))
      assert(!contents.contains("Gradient"), "Provider marks must remain monochrome")
    }
    assert(AgentProvider.allCases.allSatisfy { $0.id != "hosted" })
    let permissionKey = "detach_permission_mode_codex"
    let priorPermission = defaults.object(forKey: permissionKey)
    defer {
      if let priorPermission { defaults.set(priorPermission, forKey: permissionKey) }
      else { defaults.removeObject(forKey: permissionKey) }
    }
    defaults.removeObject(forKey: permissionKey)
    assert(DetachSettings.permissionMode(for: "codex") == .native)
    DetachSettings.setPermissionMode(.autoReview, for: "codex")
    assert(DetachSettings.permissionMode(for: "codex") == .autoReview)
    var publishedMode: AgentPermissionMode?
    let observer = NotificationCenter.default.addObserver(forName: DetachSettings.permissionModeDidChange,
      object: nil, queue: nil) { _ in publishedMode = DetachSettings.permissionMode(for: "codex") }
    DetachSettings.setPermissionMode(.supervised, for: "codex")
    NotificationCenter.default.removeObserver(observer)
    assert(publishedMode == .supervised, "Permission updates must publish after storing the new value")
    assert(DetachSettings.permissionMode(for: "pi") == .native)
    let priorInstructions = AISettings.systemPrompt
    defer { AISettings.systemPrompt = priorInstructions }
    AISettings.systemPrompt = "You are Detach, a local AI assistant that helps with coding, macOS tasks, and browser work."
    AISettings.retireDefaultPersona()
    assert(AISettings.systemPrompt.isEmpty && AISettings.additionalInstructions == nil)
    AISettings.systemPrompt = "Use my chosen checklist."
    AISettings.retireDefaultPersona()
    assert(AISettings.additionalInstructions == "Use my chosen checklist.")
    print("Provider catalog, install guidance, identifiers, and monochrome assets passed")
  }
}
