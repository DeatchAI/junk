import Foundation

/// Read-only account-routing metadata, never message bodies or an iCloud-account guess.
enum MessagesAccountDiscovery {
  static func address(in response: [String: Any]) -> String? {
    guard let chats = response["chats"] as? [[String: Any]] else { return nil }
    let addresses = chats.compactMap { chat -> String? in
      guard (chat["service"] as? String)?.lowercased() == "imessage" else { return nil }
      return clean(chat["last_addressed_handle"] as? String)
        ?? clean(chat["account_login"] as? String)
    }
    // Historical chats can belong to different accounts. Never choose between them silently.
    var unique: [String] = []
    for address in addresses where !unique.contains(where: {
      MessagesIncomingMessage.sameSender($0, address)
    }) { unique.append(address) }
    return unique.count == 1 ? unique.first : nil
  }

  private static func clean(_ raw: String?) -> String? {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    for prefix in ["E:", "P:", "mailto:", "tel:"] where value.lowercased().hasPrefix(prefix.lowercased()) {
      value = String(value.dropFirst(prefix.count))
      break
    }
    guard MessagesPairingSession(agentAddress: value) != nil else { return nil }
    return value
  }
}
