import SwiftUI

struct HistoryRowView: View {
  let conversation: Conversation
  let isSelected: Bool
  var onSelect: () -> Void
  var onHide: () -> Void
  var indentation: CGFloat = 0

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  private var title: String { conversation.title ?? "New chat" }

  var body: some View {
    HStack(spacing: 0) {
      Button(action: onSelect) {
        HStack(spacing: HistoryListMetrics.iconSpacing) {
          providerIcon
            .foregroundStyle(theme.textColor.opacity(0.5))
          Text(title).font(.appFont(size: 13))
            .foregroundStyle(theme.textColor.opacity(0.94))
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, HistoryListMetrics.rowInset + indentation)
        .frame(height: 30)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      AppActionMenu(actions: [
        .init(title: "Hide in Detach", symbol: "eye.slash", action: onHide),
      ]) {
        Image(systemName: "ellipsis").font(.system(size: 10)).frame(width: 10)
      }
      .opacity(isHovered ? 1 : 0)
      .allowsHitTesting(isHovered)
      .accessibilityLabel("Options for \(title)")
      .padding(.trailing, 2)
    }
    .background(
      theme.textColor.opacity(isSelected ? 0.075 : isHovered ? 0.04 : 0),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .onHover { isHovered = $0 }
    .help(title)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }

  @ViewBuilder private var providerIcon: some View {
    if let provider = conversation.provider.flatMap(AgentProvider.init(rawValue:)) {
      Image(provider.asset).resizable().renderingMode(.template).scaledToFit()
        .frame(width: 12, height: 12).frame(width: HistoryListMetrics.providerWidth)
        .accessibilityHidden(true)
    } else {
      Image(systemName: "bubble.left").font(.system(size: 11))
        .frame(width: HistoryListMetrics.providerWidth).accessibilityHidden(true)
    }
  }
}
