import Combine
import Foundation

// Socket double; run models, state store, and routing decisions are production code.
@MainActor
final class WebSocketManager: ObservableObject {
  @Published var isConnected = true
  @Published var isStreaming = true
  var isStoppingRun = false
  var currentConversationId: String?
  var activeChatRequest: ChatRequest?
  var stopped = 0
  var isResumingDetachedRun = false
  var resumed: ChatRequest?
  func stopStreaming() { stopped += 1; isStreaming = false; isStoppingRun = true }
  func submitChatRequest(_ request: ChatRequest) {
    resumed = request
    isStreaming = true
  }
}
