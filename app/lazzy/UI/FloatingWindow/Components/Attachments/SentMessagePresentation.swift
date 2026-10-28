import Foundation

extension ChatMessage {
  /// Recover local references exposed by imported chats without copying or rewriting history.
  func restoringAvailableAttachments() -> ChatMessage {
    var message = self
    var paths = Set<String>()
    message.attachments = (attachments + (draft?.attachments ?? [])).filter { attachment in
      attachment.isAvailable
        && paths.insert(URL(fileURLWithPath: attachment.fileRequest.path).standardizedFileURL.path).inserted
    }
    for url in ConversationPrompt.localAttachmentURLs(in: userPrompt) {
      guard !paths.contains(url.path), let attachment = AttachmentHelper.createAttachment(from: url) else { continue }
      paths.insert(url.path)
      message.attachments.append(attachment)
    }
    return message
  }
}
