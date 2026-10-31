import Foundation

@MainActor
final class RemoteConversationIndex {
  static let shared = RemoteConversationIndex()

  private let defaults: UserDefaults
  private let storageKey = "remote.conversations.machines.v1"
  private var entries: [String: String]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    entries = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
  }

  func record(conversationID: String, machineID: UUID) {
    entries[conversationID] = machineID.uuidString
    persist()
  }

  func record(_ conversations: [Conversation], machineID: UUID) {
    for conversation in conversations { entries[conversation.id] = machineID.uuidString }
    persist()
  }

  func machineID(for conversationID: String) -> UUID? {
    guard let value = entries[conversationID] else { return nil }
    return UUID(uuidString: value)
  }

  private func persist() {
    defaults.set(entries, forKey: storageKey)
  }
}
