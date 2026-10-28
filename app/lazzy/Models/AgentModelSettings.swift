import Foundation

struct AgentModelSettings: Codable, Equatable {
  let reasoningEffort: String?

  init(reasoningEffort: String? = nil) {
    self.reasoningEffort = reasoningEffort
  }
}
