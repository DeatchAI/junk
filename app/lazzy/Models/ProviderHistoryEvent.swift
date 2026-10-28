import Foundation

struct ProviderHistoryEvent: Decodable {
  let type: String
  let syncing: Bool?
  let indexing: Bool?
  let pending: Int?
  let indexedChats: Int?
  let revision: Int?
  let catalogRevision: Int?
  let notices: [String]?
  let requestId: String?
  let query: String?
  let conversations: [Conversation]?
  let conversation: Conversation?
  let runId: String?
  let error: String?

  static func parse(_ data: Data) -> Self? {
    guard let event = try? JSONDecoder().decode(Self.self, from: data),
      ["provider_history_status", "history_search_results", "provider_session", "history_error"].contains(event.type)
    else { return nil }
    return event
  }
}

struct ProviderHistoryRequest: Encodable {
  let type: String
  var requestId: String?
  var query: String?
}
