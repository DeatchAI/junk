import Foundation

enum AgentPermissionMode: String, CaseIterable, Identifiable {
  case native
  case supervised
  case autoReview = "auto"

  var id: String { rawValue }
  var title: String {
    switch self {
    case .native: return "Agent default"
    case .supervised: return "Ask for approval"
    case .autoReview: return "Automatic review"
    }
  }

  func title(for agent: String) -> String {
    agent == "claude" && self == .supervised ? "Standard policy" : title
  }

  var detail: String {
    switch self {
    case .native: return "Uses the agent's configuration and saved session permissions."
    case .supervised: return "Codex asks through Detach. Claude uses its standard permission policy."
    case .autoReview: return "The agent reviews access requests automatically within its safety policy."
    }
  }

  static func supportsOverrides(for agent: String) -> Bool {
    ["codex", "claude"].contains(agent)
  }
}
