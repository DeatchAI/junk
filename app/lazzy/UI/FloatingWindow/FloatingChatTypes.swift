import Foundation
import SwiftUI

/// A single chat exchange: user prompt + optional AI response
struct ChatMessage: Identifiable {
  let id = UUID()
  var userMessageId: String?  // Backend ID for user message
  var assistantMessageId: String?  // Backend ID for assistant message
  let userPrompt: String
  let context: [DetectedContent]?  // Contexts available for this message
  var aiResponse: String?
  var isLiked: Bool? = nil  // nil = no vote, true = liked, false = disliked

  var isComplete: Bool { aiResponse != nil }
}

struct AgentResponseEvent: Identifiable {
  enum Kind {
    case text
    case activity
  }

  let id = UUID()
  var kind: Kind
  var text: String
  var isActive: Bool = false
}
