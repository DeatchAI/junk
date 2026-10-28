import Foundation
import SwiftUI

extension FloatingChatView {
  var composerDraft: ComposerDraft {
    ComposerDraft(text: inputText, attachments: pendingAttachments, contexts: sessionContexts,
      skills: pendingSkills, browserTabs: pendingBrowserTabs, mcpAttachments: pendingMCPAttachments,
      commands: pendingCommandAliases)
  }

  var canReviseMessages: Bool {
    !wsManager.isStreaming && !wsManager.isStoppingRun && !isThinking
      && (wsManager.currentConversation?.isProviderHistory != true || wsManager.currentConversation?.canResume != false)
  }

  func applyDraft(_ draft: ComposerDraft) {
    editorDocumentID = UUID()
    pendingAttachments = draft.attachments.filter(\.isAvailable)
    sessionContexts = draft.contexts
    pendingSkills = draft.skills
    pendingBrowserTabs = draft.browserTabs
    pendingMCPAttachments = draft.mcpAttachments
    pendingCommandAliases = draft.commands
    let text = ComposerInlineToken.removingMissingFiles(from: draft.text, attachments: pendingAttachments)
    inputText = ComposerInlineToken.addingMissingFiles(to: text, attachments: pendingAttachments, contexts: draft.contexts)
    isInputFocused = true
  }

  func reviseMessage(_ index: Int) {
    guard canReviseMessages, messages.indices.contains(index),
      let reference = messages[index].branchReference, reference.canBranch else { return }
    conversationStore.cancelAttachment()
    conversationStore.cancelSearch()
    let message = messages[index].restoringAvailableAttachments()
    messages[index].attachments = message.attachments
    var original = message.draft ?? ComposerDraft(text: ConversationPrompt.readable(message.userPrompt),
      attachments: message.attachments, contexts: message.context ?? [])
    original.text = ConversationPrompt.readable(original.text)
    original.attachments = message.attachments
    revisionTarget = ConversationBranchFrom(messageId: reference.messageId, promptHash: reference.promptHash)
    errorMessage = nil
    let draft = revisionSession.begin(messageNumber: index + 1, currentDraft: composerDraft, original: original)
    applyDraft(draft)
  }

  func cancelMessageRevision() {
    guard let draft = revisionSession.finish() else { return }
    applyDraft(draft)
    revisionTarget = nil
    errorMessage = nil
  }

  func clearSentDraft() {
    // Text context remains available for ordinary follow-ups; files belong to a message.
    let retainedContexts = sessionContexts
    applyDraft(ComposerDraft(contexts: retainedContexts))
    if let saved = revisionSession.finish() { applyDraft(saved) }
    revisionTarget = nil
  }

  func retainSentAttachments(conversationID: String? = nil) {
    guard !AISettings.zeroDataRetention,
      let id = conversationID ?? wsManager.currentConversationId else { return }
    SentMessageAttachmentStore.save(messages, conversationID: id)
  }

  func validateDraftAttachments() -> Bool {
    if composerDraft.resolvedText.range(of: #"\[\[(?:file:[A-Fa-f0-9-]{36}|context:[a-f0-9]{64})\]\]"#,
      options: .regularExpression) != nil {
      errorMessage = "An attachment is no longer available. Remove its pill and attach it again."
      return false
    }
    let missing = pendingAttachments.filter { !FileManager.default.fileExists(atPath: $0.fileRequest.path) }
    guard !missing.isEmpty else { return true }
    errorMessage = "Attachments are no longer available: \(missing.map(\.fileName).joined(separator: ", ")). Remove them or attach them again."
    return false
  }
}
