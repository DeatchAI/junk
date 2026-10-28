import Foundation

extension WebSocketManager {
  func handleAgentQuestion(_ data: Data) -> Bool {
    AgentQuestionCenter.shared.handle(data, owner: ObjectIdentifier(self)) { [weak self] response in
      self?.sendQuestionAnswer(response)
    }
  }
  func dismissAgentQuestions() {
    AgentQuestionCenter.shared.cancel(owner: ObjectIdentifier(self))
  }
}
