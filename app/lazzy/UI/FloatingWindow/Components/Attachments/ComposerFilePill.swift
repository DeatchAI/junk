import SwiftUI

/// Non-media attachments share one compact, readable treatment.
struct ComposerFilePill: View {
  let attachment: ChatAttachment
  var onRemove: (() -> Void)?
  @ObservedObject private var theme = ThemeManager.shared

  private var symbol: String {
    if attachment.conversationID != nil { return "bubble.left" }
    if attachment.fileRequest.mimeType == "inode/directory" { return "folder" }
    return "doc.text"
  }

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: symbol).font(.system(size: 11))
      Text(attachment.fileName)
        .font(.appFont(size: 12))
        .lineLimit(1).truncationMode(.middle)
        .frame(maxWidth: 170, alignment: .leading)
      if let onRemove {
        Button(action: onRemove) {
          Image(systemName: "xmark").font(.system(size: 8, weight: .medium))
            .frame(width: 18, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(theme.secondaryTextColor)
        .accessibilityLabel("Remove \(attachment.fileName)")
      }
    }
    .foregroundStyle(theme.textColor.opacity(0.85))
    .padding(.leading, 8).padding(.trailing, onRemove == nil ? 8 : 3).padding(.vertical, 3)
    .background(theme.textColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 7))
    .help(attachment.conversationID == nil ? attachment.fileRequest.path
      : "\(attachment.fileName) · Conversation text attached")
  }
}
