import Foundation

struct AgentCapability: Codable, Identifiable, Equatable {
  let id: String
  let displayName: String
  let installed: Bool
  let executablePath: String?
  let authHint: String?
  let models: [AgentModelCapability]
  let defaultModel: String?
}

struct AgentModelCapability: Codable, Identifiable, Equatable {
  let id: String
  let displayName: String
  let reasoningEfforts: [String]?
  let defaultReasoningEffort: String?
  let reasoningLabel: String?
}
