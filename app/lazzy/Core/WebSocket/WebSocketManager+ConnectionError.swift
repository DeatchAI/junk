import Foundation

extension WebSocketManager {
  func handleConnectionError(_ error: Error) {
    endDesktopSessions()
    cancelAutoRouting()
    cancelConversationLoad()
    providerHistory.connectionLost()
    dismissAgentQuestions()
    let hadActiveRun = isStreaming || isStoppingRun
    isStoppingRun = false
    if let runId = activeChatRequest?.runId, hadActiveRun {
      onRunConnectionLost?(runId, error.localizedDescription)
    }
    isConnected = false
    isConnecting = false
    isLoadingMCPServers = false
    isStreaming = false
    lastError = error.localizedDescription
    onError?(error.localizedDescription)

    // Try to reconnect after delay
    print("🔄 Will retry in 3 seconds...")
    Task {
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      connect()
    }
  }
}
