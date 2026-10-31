import SwiftUI

/// Project expansion and the visible chat count belong to each project independently.
struct HistoryProjectSection: View {
  let group: HistoryProviderGroup
  let selectedConversationID: String?
  let isSearching: Bool
  let onSelect: (Conversation) -> Void
  let onHide: (Conversation) -> Void

  private static let pageSize = 6
  @State private var projectExpanded = true
  @State private var searchExpanded = true
  @State private var visibleCount = HistoryProjectSection.pageSize
  @State private var headerHovered = false
  @State private var moreHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  private var expanded: Bool { isSearching ? searchExpanded : projectExpanded }
  private var visibleConversations: [Conversation] {
    isSearching ? group.conversations : Array(group.conversations.prefix(visibleCount))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      header
      if expanded {
        ForEach(visibleConversations) { conversation in
          HistoryRowView(
            conversation: conversation,
            isSelected: selectedConversationID == conversation.id,
            onSelect: { onSelect(conversation) },
            onHide: { onHide(conversation) },
            indentation: HistoryListMetrics.chatIndent
          )
        }
        if !isSearching && visibleCount < group.conversations.count {
          showMore
        }
      }
    }
    .onChange(of: isSearching) { _, searching in
      if searching { searchExpanded = true }
    }
  }

  private var header: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.16)) {
        if isSearching { searchExpanded.toggle() }
        else { projectExpanded.toggle() }
      }
    } label: {
      HStack(spacing: HistoryListMetrics.iconSpacing) {
        ComposerFolderIcon().frame(width: 16, height: 16)
        Text(group.name).font(.appFont(size: 12.5)).fontWeight(.medium)
          .lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 8, weight: .medium))
          .rotationEffect(.degrees(expanded ? 90 : 0))
          .foregroundStyle(theme.textColor.opacity(headerHovered ? 0.7 : 0.35))
      }
      .foregroundStyle(theme.textColor.opacity(0.74))
      .padding(.horizontal, HistoryListMetrics.rowInset)
      .frame(height: 30)
      .background(theme.textColor.opacity(headerHovered ? 0.035 : 0),
                  in: RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { headerHovered = $0 }
    .help(group.workspacePath ?? group.name)
    .accessibilityLabel("\(group.name), \(group.conversations.count) chats")
    .accessibilityValue(expanded ? "Expanded" : "Collapsed")
  }

  private var showMore: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.16)) {
        visibleCount = min(visibleCount + Self.pageSize, group.conversations.count)
      }
    } label: {
      Text("Show more")
        .font(.appFont(size: 12))
        .foregroundStyle(theme.textColor.opacity(moreHovered ? 0.85 : 0.46))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, HistoryListMetrics.chatTitleInset)
        .padding(.trailing, HistoryListMetrics.rowInset)
        .frame(height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { moreHovered = $0 }
    .accessibilityLabel("Show more chats in \(group.name)")
  }
}

enum HistoryListMetrics {
  static let rowInset: CGFloat = 12
  static let chatIndent: CGFloat = 18
  static let providerWidth: CGFloat = 14
  static let iconSpacing: CGFloat = 8
  static let chatTitleInset = rowInset + chatIndent + providerWidth + iconSpacing
}
