import SwiftUI

struct ComposerConversationChip: View {
  let attachment: ChatAttachment
  var onRemove: (() -> Void)?
  var body: some View {
    ComposerFilePill(attachment: attachment, onRemove: onRemove)
  }
}
