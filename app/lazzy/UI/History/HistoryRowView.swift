import SwiftUI

struct HistoryRowView: View {
  let conversation: Conversation
  let isSelected: Bool
  var onSelect: () -> Void
  var onHide: () -> Void

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 8) {
        if let provider = conversation.provider.flatMap(AgentProvider.init(rawValue:)) {
          Image(provider.asset).resizable().renderingMode(.template).scaledToFit()
            .frame(width: 14, height: 14).frame(width: 16).accessibilityHidden(true)
        } else {
          Image(systemName: "bubble.left").font(.system(size: 13)).frame(width: 16).accessibilityHidden(true)
        }
        Text(conversation.title ?? "New chat").font(.system(size: 14, weight: .regular))
          .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
      }
      .foregroundStyle(theme.textColor)
      .padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(
      theme.textColor.opacity(isSelected ? 0.075 : isHovered ? 0.04 : 0),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(theme.textColor.opacity(isSelected ? 0.11 : 0), lineWidth: 0.5).allowsHitTesting(false) }
    .onHover { isHovered = $0 }
    .help(conversation.title ?? "New chat")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .contextMenu { Button("Hide in Detach", systemImage: "eye.slash", action: onHide) }
  }
}
