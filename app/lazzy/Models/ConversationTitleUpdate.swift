import Foundation

struct ConversationTitleUpdate: Decodable {
  let type: String
  let conversationId: String
  let title: String

  static func parse(_ data: Data) -> ConversationTitleUpdate? {
    guard let update = try? JSONDecoder().decode(Self.self, from: data),
      update.type == "conversation_title", !update.conversationId.isEmpty,
      !update.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      update.title.count <= 72, !update.title.contains("\n") else { return nil }
    return update
  }
}

/// Live metadata wins over an older history-list response already in flight.
struct ConversationTitleCache {
  private var titles: [String: String] = [:]
  mutating func record(_ update: ConversationTitleUpdate) { titles[update.conversationId] = update.title }
  func title(for id: String) -> String? { titles[id] }
  func merging(_ conversations: [Conversation]) -> [Conversation] {
    conversations.map { conversation in
      // Provider renames are authoritative, even if Detach previously saw another title.
      if conversation.isProviderHistory { return conversation }
      return titles[conversation.id].map { conversation.named($0) } ?? conversation
    }
  }
  mutating func remove(_ id: String) { titles[id] = nil }
}
