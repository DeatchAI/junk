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
  var responseParts: [MessagePart] = []
  var isLiked: Bool? = nil  // nil = no vote, true = liked, false = disliked
  var attachments: [ChatAttachment] = []
  var draft: ComposerDraft? = nil
  var branchReference: ConversationMessageReference? = nil
  var gitRunID: String? = nil
  var gitTimestamp: Int? = nil
  var gitMessageOrdinal: Int? = nil
  var gitRevision = 0

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
  var activity: AgentActivityEvent?
  var toolName: String?

  var messagePart: MessagePart {
    guard kind == .activity else { return MessagePart(type: "text", text: text) }
    let details = activity?.details ?? [:]
    let detailText = details.isEmpty ? activity?.subtitle : ActivityJSONValue.object(details).displayText
    let activityKind = activity?.kind ?? "tool"
    // Provider titles can contain entire shell programs. Keep those in disclosure details.
    let label = activityKind == "command" ? (isActive ? "Running command" : "Ran command")
      : activityKind == "file_change" ? (isActive ? "Updating files" : "Updated files") : text
    return MessagePart(type: "activity", text: detailText, id: activity?.id,
      title: label, kind: activityKind, status: activity?.phase == "failed" ? "failed" : isActive ? "started" : "completed",
      command: details["command"]?.displayText, output: details["output"]?.displayText, toolName: toolName)
  }
}
