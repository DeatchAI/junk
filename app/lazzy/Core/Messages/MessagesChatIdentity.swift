import Foundation

/// Watch notifications do not provide an authoritative service field.
/// Read this metadata with chats.get for the exact chat that sent the code.
struct MessagesChatIdentity {
  let id: Int
  let service: String
  let isGroup: Bool
  let participants: [String]

  init?(_ value: [String: Any]) {
    guard let id = value["id"] as? Int, id > 0,
      let service = value["service"] as? String,
      let isGroup = value["is_group"] as? Bool,
      let participants = value["participants"] as? [String] else { return nil }
    self.id = id
    self.service = service.trimmingCharacters(in: .whitespacesAndNewlines)
    self.isGroup = isGroup
    self.participants = participants
  }

  func rejectionReason(chatID: Int, sender: String) -> String? {
    guard id == chatID else {
      return "Messages returned details for a different conversation. Create a new QR and try again."
    }
    guard !isGroup else {
      return "Messages marks this as a group conversation. Send the code in a new one-to-one conversation."
    }
    guard service.caseInsensitiveCompare("iMessage") == .orderedSame else {
      if service.caseInsensitiveCompare("SMS") == .orderedSame
        || service.caseInsensitiveCompare("RCS") == .orderedSame {
        return "Messages reports this conversation as \(service). Send the code to the agent’s iMessage email address."
      }
      return "Messages has not identified this chat’s service. Start a new iMessage to the agent’s email and send the code again."
    }
    guard participants.contains(where: { MessagesIncomingMessage.sameSender($0, sender) }) else {
      return "Messages has not confirmed this sender in the conversation yet. Send the pairing code again."
    }
    return nil
  }
}
