import Foundation

struct MessagesPairingSession: Equatable {
  let agentAddress: String
  let token: String
  let expiresAt: Date

  init?(agentAddress: String, now: Date = .now, token: String = UUID().uuidString) {
    let address = agentAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    let phone = address.filter(\.isNumber)
    let emailParts = address.split(separator: "@", omittingEmptySubsequences: false)
    let isEmail = emailParts.count == 2 && emailParts.allSatisfy { !$0.isEmpty }
    let isPhone = (7...15).contains(phone.count)
      && address.allSatisfy { $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
      && address.filter({ $0 == "+" }).count <= 1
      && (!address.contains("+") || address.hasPrefix("+"))
    guard !address.contains(where: \.isWhitespace), isEmail || isPhone else { return nil }
    self.agentAddress = address
    self.token = token.replacingOccurrences(of: "-", with: "").uppercased()
    expiresAt = now.addingTimeInterval(300)
  }

  var messageText: String { "pair \(token)" }

  /// A draft only. iPhone scanners may omit the body; the UI also exposes Copy code.
  var composeURL: URL {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    let recipient = agentAddress.addingPercentEncoding(withAllowedCharacters: safe.union(
      CharacterSet(charactersIn: "@+")))!
    let body = messageText.addingPercentEncoding(withAllowedCharacters: safe)!
    return URL(string: "sms:\(recipient)?body=\(body)")!
  }

  func accepts(_ text: String, at date: Date = .now) -> Bool {
    date < expiresAt && text.trimmingCharacters(in: .whitespacesAndNewlines)
      .caseInsensitiveCompare(messageText) == .orderedSame
  }
}

struct MessagesIncomingMessage {
  let id: Int
  let chatID: Int
  let sender: String
  let text: String
  let isFromMe: Bool
  let isGroup: Bool
  let poll: MessagesNativePoll?
  let isPollEvent: Bool

  init?(_ envelope: [String: Any]) {
    guard let params = envelope["params"] as? [String: Any],
      let value = params["message"] as? [String: Any],
      value["type"] == nil,
      let id = value["id"] as? Int, id > 0,
      let chatID = value["chat_id"] as? Int, chatID > 0,
      let sender = value["sender"] as? String, !sender.isEmpty,
      let text = value["text"] as? String,
      let isFromMe = value["is_from_me"] as? Bool
    else { return nil }
    let guid = value["chat_guid"] as? String ?? ""
    let group = value["is_group"] as? Bool
      ?? (guid.contains(";+;") ? true : guid.contains(";-;") ? false : nil)
    guard let group else { return nil }
    self.id = id
    self.chatID = chatID
    self.sender = sender
    self.text = text
    self.isFromMe = isFromMe
    isGroup = group
    isPollEvent = value["poll"] != nil
    poll = (value["poll"] as? [String: Any]).flatMap(MessagesNativePoll.init)
  }

  static func sameSender(_ lhs: String, _ rhs: String) -> Bool {
    let left = lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let right = rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if left.contains("@") || right.contains("@") { return left == right }
    let a = left.filter(\.isNumber), b = right.filter(\.isNumber)
    return !a.isEmpty && a == b
  }
}
