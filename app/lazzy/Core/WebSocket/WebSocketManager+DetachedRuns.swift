import Foundation

extension WebSocketManager {
  /// Continue in saved conversation context, with the original provider and capabilities.
  /// This starts a new turn, not a simulated pause/unpause of a CLI process.
  func continueDetachedRun(_ request: ChatRequest, conversationId: String) {
    guard isConnected, !isStreaming, !isStoppingRun else { return }
    isResumingDetachedRun = true
    defer { isResumingDetachedRun = false }
    submitChatRequest(request.continuation(in: conversationId))
  }
}
