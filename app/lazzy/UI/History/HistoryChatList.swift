import SwiftUI

struct HistoryChatList: View {
  @ObservedObject var manager: WebSocketManager
  let groups: [HistoryProviderGroup]
  let isSearching: Bool
  let isPresented: Bool
  let onSelect: (Conversation) -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 14) {
        ForEach(groups) { group in
          HistoryProjectSection(
            group: group,
            selectedConversationID: manager.currentConversationId,
            isSearching: isSearching,
            onSelect: onSelect,
            onHide: { manager.deleteConversation(id: $0.id) }
          )
        }
        if !isSearching && manager.hasMoreConversations {
          loadOlderChats
        }
      }
      .padding(.top, 4)
      .padding(.bottom, 8)
    }
    .scrollIndicators(.hidden)
  }

  /// Explicit loading prevents collapsed projects from repeatedly fetching pages
  /// just because their shortened lists no longer fill the scroll viewport.
  private var loadOlderChats: some View {
    Button { manager.loadMoreConversations() } label: {
      HStack(spacing: 7) {
        if manager.isLoadingMoreConversations { AppSpinner() }
        Text(manager.isLoadingMoreConversations ? "Loading older chats…" : "Load older chats")
          .font(.appFont(size: 11))
      }
      .foregroundStyle(theme.secondaryTextColor)
      .frame(maxWidth: .infinity)
      .frame(height: 30)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isPresented || !manager.isConnected || manager.isLoadingMoreConversations)
    .accessibilityLabel("Load older chats from your agents")
  }
}
