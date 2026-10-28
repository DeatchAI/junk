import SwiftUI

/// Two bounded rows keep the text and toolbar reachable even with many files.
struct ComposerAttachmentList: View {
  let attachments: [ChatAttachment]
  var onRemove: ((ChatAttachment) -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      let available = attachments.filter(\.isAvailable)
      attachmentRow(available.filter(\.canPreviewMedia), height: 56)
      attachmentRow(available.filter { !$0.canPreviewMedia }, height: 28)
    }
  }

  @ViewBuilder private func attachmentRow(_ files: [ChatAttachment], height: CGFloat) -> some View {
    if !files.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 7) {
          ForEach(files) { attachment in
            ComposerAttachmentPreview(attachment: attachment,
              onRemove: onRemove.map { remove in { remove(attachment) } })
          }
        }
        .padding(.top, 2).padding(.trailing, 3)
      }
      .frame(height: height, alignment: .topLeading)
    }
  }
}
