import SwiftUI

/// Previewable media stays visual; every other attachment is a named pill.
struct ComposerAttachmentPreview: View {
  let attachment: ChatAttachment
  var onRemove: (() -> Void)?

  @State private var isHovered = false

  var body: some View {
    if attachment.canPreviewMedia {
      filePreview
    } else {
      ComposerFilePill(attachment: attachment, onRemove: onRemove)
    }
  }

  private var filePreview: some View {
    Button { ComposerMediaPreviewController.shared.show(attachment) } label: {
      thumbnail
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Preview \(attachment.fileName)")
    .overlay(alignment: .topTrailing) {
      if let onRemove {
        Button(action: onRemove) {
          Image(systemName: "xmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(.black, in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? 1 : 0)
        .allowsHitTesting(isHovered)
        .accessibilityLabel("Remove \(attachment.fileName)")
      }
    }
    .onHover { isHovered = $0 }
    .help(attachment.isMedia ? "Preview \(attachment.fileName)" : attachment.fileName)
    .accessibilityAction(named: Text("Remove attachment")) { onRemove?() }
    .contextMenu {
      if attachment.isMedia {
        Button("Preview", systemImage: "eye") { ComposerMediaPreviewController.shared.show(attachment) }
      }
      if let onRemove {
        Button("Remove attachment", systemImage: "xmark", action: onRemove)
      }
    }
  }

  private var thumbnail: some View {
    Image(nsImage: attachment.thumbnail)
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: 52, height: 52)
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay(alignment: .bottomTrailing) {
        if attachment.fileRequest.mimeType.hasPrefix("video/") {
          Image(systemName: "play.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .padding(3)
            .background(.black.opacity(0.68), in: Circle())
            .padding(1)
            .allowsHitTesting(false)
        }
      }
  }
}
