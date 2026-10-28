import Foundation

struct MessagePart: Codable, Equatable {
  var type: String
  var text: String? = nil
  var id: String? = nil
  var title: String? = nil
  var kind: String? = nil
  var status: String? = nil
  var command: String? = nil
  var output: String? = nil
  var toolName: String? = nil
}

struct Message: Codable, Identifiable {
  let id: String
  let conversation_id: String
  let role: String
  let content: String
  let parts: [MessagePart]?
  let created_at: Int

  var createdDate: Date { Date(timeIntervalSince1970: TimeInterval(created_at) / 1000) }
  var isUser: Bool { role == "user" }
  var isAssistant: Bool { role == "assistant" }
}
