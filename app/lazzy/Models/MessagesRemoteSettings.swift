import Foundation

final class MessagesRemoteSettings {
  private let defaults: UserDefaults
  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  var enabled: Bool {
    get { defaults.bool(forKey: "messages_remote.enabled") }
    set { defaults.set(newValue, forKey: "messages_remote.enabled") }
  }
  var pollsEnabled: Bool {
    get { defaults.bool(forKey: "messages_remote.polls_enabled") }
    set { defaults.set(newValue, forKey: "messages_remote.polls_enabled") }
  }
  var sender: String? {
    get { defaults.string(forKey: "messages_remote.sender") }
    set { defaults.set(newValue, forKey: "messages_remote.sender") }
  }
  var agentAddress: String {
    get { defaults.string(forKey: "messages_remote.agent_address") ?? "" }
    set { defaults.set(newValue, forKey: "messages_remote.agent_address") }
  }
  var chatID: Int? {
    get {
      guard defaults.object(forKey: "messages_remote.chat_id") != nil else { return nil }
      return defaults.integer(forKey: "messages_remote.chat_id")
    }
    set { defaults.set(newValue, forKey: "messages_remote.chat_id") }
  }
  func pair(chatID: Int, sender: String) {
    self.chatID = chatID
    self.sender = sender
    enabled = true
  }
  func clearPairing() {
    enabled = false
    sender = nil
    chatID = nil
  }
}
