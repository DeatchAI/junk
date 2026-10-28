import Combine
import Foundation

@MainActor final class WebSocketManager: ObservableObject {
  @Published var isConnected = true
  @Published var conversations: [Conversation] = []
  @Published var hasMoreConversations = false
  @Published var isLoadingMoreConversations = false
  var currentConversationId: String?
  let providerHistory = ProviderHistoryState()
  var requests: [[String: Any]] = []
  func sendRequest<T: Encodable>(_ request: T, label: String) {
    requests.append(try! JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any])
  }
  func listConversations() {}
  func refreshHistoryListing() {}
  func deleteConversation(id: String) {}
  func loadMoreConversations() {}
}

@MainActor final class HistoryWindowController: ObservableObject {
  @Published var placement: ActivityIslandPlacement = .left
  @Published var isVisible = true
}
