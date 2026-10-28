import SwiftUI

extension FloatingChatInputView {
  func completeConversationAttachment(_ conversation: Conversation) {
    guard !fileAttachments.contains(where: { $0.conversationID == conversation.id }) else { return }
    conversationStore.attach(conversation) { attachment in
      // Conversation searches can contain spaces. Consume the whole search
      // phrase while retaining the draft that came before its @ trigger.
      if let offset = mentionTriggerOffset, offset < inputText.count {
        let start = inputText.index(inputText.startIndex, offsetBy: offset)
        if inputText[start] == "@" {
          let end = inputText[start...].firstIndex(of: "\n") ?? inputText.endIndex
          inputText.removeSubrange(start..<end)
        }
      }
      onAttachAttachment(attachment)
      dismissAttachmentMenu()
      isInputFocused.wrappedValue = true
    }
  }
}
