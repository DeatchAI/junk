import Foundation

extension WebSocketManager {
  func requestConversationBranches() {
    guard isConnected, let id = currentConversationId else { return }
    sendRequest(["type": "get_conversation_branches", "conversationId": id], label: "get_conversation_branches")
  }

  func handleConversationBranches(_ data: Data) -> Bool {
    guard let state = try? JSONDecoder().decode(ConversationBranchState.self, from: data),
      state.type == "conversation_branch_state" else { return false }
    if state.conversationId == currentConversationId { conversationBranchState = state }
    return true
  }
}
