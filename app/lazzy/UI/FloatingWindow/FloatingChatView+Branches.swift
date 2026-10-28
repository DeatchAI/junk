import Foundation
import SwiftUI

extension FloatingChatView {
  var availableBranches: [ConversationBranch] {
    guard wsManager.conversationBranchState?.conversationId == wsManager.currentConversationId else { return [] }
    return wsManager.conversationBranchState?.branches ?? []
  }

  func applyBranchReferences(_ state: ConversationBranchState?) {
    guard let state, state.conversationId == wsManager.currentConversationId else { return }
    // Match a full native exchange list, never an ambiguous repeated prompt on a partial page.
    guard state.messages.count == messages.count else { return }
    for index in messages.indices {
      let reference = state.messages[index]
      guard reference.promptHash == ConversationPrompt.fingerprint(messages[index].userPrompt) else { continue }
      messages[index].userMessageId = reference.messageId
      messages[index].branchReference = reference
    }
    retainSentAttachments()
  }

  func rememberBranch(draft: ComposerDraft? = nil) {
    guard let id = wsManager.currentConversationId else { return }
    let draft = draft ?? composerDraft
    branchSnapshots[id] = ComposerBranchSnapshot(messages: messages, draft: draft,
      selectedMessage: activeMessageIndex, response: lastCompletedResponse)
    ComposerBranchDraftStore.save(draft, conversationID: id, selectedMessage: activeMessageIndex)
  }

  func switchConversationBranch(_ id: String) {
    guard id != wsManager.currentConversationId, availableBranches.contains(where: { $0.id == id }),
      !wsManager.isStreaming, !isThinking else { return }
    cancelMessageRevision()
    rememberBranch()
    retainSentAttachments()
    let snapshot = branchSnapshots[id]
    applyDraft(snapshot?.draft ?? ComposerBranchDraftStore.load(id)?.draft ?? ComposerDraft())
    messages = snapshot?.messages ?? []
    activeMessageIndex = snapshot?.selectedMessage
    lastCompletedResponse = snapshot?.response ?? ""
    streamingResponse = ""; responseEvents = []; errorMessage = nil
    loadingBranchID = id
    wsManager.loadConversation(id: id)
    wsManager.requestConversationBranches()
  }

  func acceptBranchSession(_ conversation: Conversation) {
    guard let submission = branchSubmission, conversation.id != submission.sourceID else { return }
    messages = Array(messages.prefix(submission.messageIndex))
    messages.append(ChatMessage(userPrompt: submission.draft.resolvedText, context: submission.draft.contexts,
      aiResponse: nil, attachments: submission.draft.attachments, draft: submission.draft))
    activeMessageIndex = nil
    branchSubmission = nil
    branchRecoveryDraft = submission.draft
    clearSentDraft()
    revisionTarget = nil
    retainSentAttachments(conversationID: conversation.id)
  }

  func beginBranchSubmission(_ draft: ComposerDraft) -> ConversationBranchFrom? {
    guard let number = revisionSession.messageNumber, let target = revisionTarget,
      let sourceID = wsManager.currentConversationId else { return nil }
    rememberBranch(draft: revisionSession.originalDraft)
    branchSubmission = ComposerBranchSubmission(sourceID: sourceID, messageIndex: number - 1, draft: draft)
    return target
  }

  func handleBranchError() {
    branchSubmission = nil
    if let draft = branchRecoveryDraft {
      applyDraft(draft)
      branchRecoveryDraft = nil
    }
  }
}
