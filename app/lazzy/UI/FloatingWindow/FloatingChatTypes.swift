import Foundation
import SwiftUI

enum ComposerOutputMode: String, CaseIterable, Identifiable {
  case agent = "Agent"
  case image = "Image"
  case video = "Video"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .agent: return "text.bubble"
    case .image: return "photo"
    case .video: return "video"
    }
  }
}

/// A single chat exchange: user prompt + optional AI response
struct ChatMessage: Identifiable {
  let id = UUID()
  var userMessageId: String?  // Backend ID for user message
  var assistantMessageId: String?  // Backend ID for assistant message
  let userPrompt: String
  let context: [DetectedContent]?  // Contexts available for this message
  var aiResponse: String?
  var mediaJob: MediaJob? = nil
  var isLiked: Bool? = nil  // nil = no vote, true = liked, false = disliked

  var isComplete: Bool { aiResponse != nil || mediaJob?.isTerminal == true }
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
  var activity: AgentActivityEvent?
  var toolName: String?
}
