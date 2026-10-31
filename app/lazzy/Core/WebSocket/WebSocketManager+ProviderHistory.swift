import Foundation

extension WebSocketManager {
  func cancelConversationLoad() {
    conversationLoadTask?.cancel()
    conversationLoadTask = nil
    conversationLoadID = nil
  }

  func getConversation(id: String) {
    cancelConversationLoad()
    guard isConnected, let session else { return }
    let loadID = UUID()
    conversationLoadID = loadID
    let request = HistoryConversationLoader.request(id: id, endpoint: runtimeEndpoint)
    conversationLoadTask = Task { [weak self] in
      defer {
        if self?.conversationLoadID == loadID {
          self?.conversationLoadTask = nil
          self?.conversationLoadID = nil
        }
      }
      do {
        let entry = try await HistoryConversationLoader.load(request, id: id, using: session)
        guard !Task.isCancelled, let self, self.conversationLoadID == loadID,
          self.currentConversationId == id, self.isConnected else { return }
        self.lastError = nil
        self.providerHistory.error = nil
        self.handleServerMessage(.conversation(conversation: entry.conversation, messages: entry.messages))
      } catch {
        guard !Task.isCancelled, let self, self.conversationLoadID == loadID,
          self.currentConversationId == id else { return }
        // A history read failure must not disconnect or stop a live agent.
        self.providerHistory.error = error.localizedDescription
        if !self.isStreaming {
          self.lastError = error.localizedDescription
          self.onError?(error.localizedDescription)
        }
      }
    }
  }

  func refreshHistoryListing() {
    guard isConnected else { return }
    let count = max(500, min(10_000, conversations.count))
    sendRequest(ListConversationsRequest(limit: count, offset: 0, refreshLoaded: true), label: "list_conversations")
  }

  func handleProviderHistory(_ data: Data) -> Bool {
    guard let event = ProviderHistoryEvent.parse(data) else { return false }
    if event.type == "provider_session" {
      guard event.runId == activeChatRequest?.runId, let conversation = event.conversation else { return true }
      if activeChatRequest?.branchFrom != nil { autoRoutedChoice = nil }
      currentConversationId = conversation.id
      currentConversationTitle = conversation.title
      currentConversation = conversation
      onProviderSession?(conversation)
      if let index = conversations.firstIndex(where: { $0.id == conversation.id }) { conversations[index] = conversation }
      else { conversations.insert(conversation, at: 0) }
      if let title = conversation.title { onConversationTitleUpdated?(conversation.id, title) }
    } else {
      providerHistory.handle(event, using: self)
    }
    return true
  }
}
