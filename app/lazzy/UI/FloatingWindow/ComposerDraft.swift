import Foundation

/// An in-memory draft includes selections as well as the visible editor text.
struct ComposerDraft {
  var text = ""
  var attachments: [ChatAttachment] = []
  var contexts: [DetectedContent] = []
  var skills: [SkillAttachment] = []
  var browserTabs: [BrowserTabAttachment] = []
  var mcpAttachments: [ComposerMCPAttachment] = []
  var commands: [SlashCommandAlias] = []

  var files: [FileAttachmentRequest] {
    var seen = Set<String>()
    return (contexts.flatMap { $0.files ?? [] } + attachments.map(\.fileRequest))
      .filter { seen.insert($0.path).inserted }
  }
}

struct ComposerRevisionSession {
  private(set) var messageNumber: Int?
  private var savedDraft: ComposerDraft?
  var originalDraft: ComposerDraft? { savedDraft }

  mutating func begin(messageNumber: Int, currentDraft: ComposerDraft, original: ComposerDraft) -> ComposerDraft {
    // Choosing another past message must not overwrite the user's first draft.
    if savedDraft == nil { savedDraft = currentDraft }
    self.messageNumber = messageNumber
    return original
  }

  mutating func finish() -> ComposerDraft? {
    defer { self = ComposerRevisionSession() }
    return savedDraft
  }
}
