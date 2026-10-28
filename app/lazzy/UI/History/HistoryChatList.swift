import SwiftUI

struct HistoryChatList: View {
  @ObservedObject var manager: WebSocketManager
  let groups: [HistoryProviderGroup]
  let isSearching: Bool
  let isPresented: Bool
  let onSelect: (Conversation) -> Void
  @ObservedObject private var theme = ThemeManager.shared
  @State private var bottomY: CGFloat = .infinity

  var body: some View {
    GeometryReader { viewport in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(groups) { group in
            Section {
              ForEach(group.conversations) { conversation in
                HistoryRowView(conversation: conversation, isSelected: manager.currentConversationId == conversation.id,
                  onSelect: { onSelect(conversation) }, onHide: { manager.deleteConversation(id: conversation.id) })
              }
            } header: {
              projectHeader(group)
            }
          }
          Color.clear.frame(height: 1).background {
            GeometryReader { marker in
              Color.clear.preference(key: HistoryBottomPosition.self, value: marker.frame(in: .named("historyScroll")).minY)
            }
          }.accessibilityHidden(true)
        }.padding(.bottom, 8)
      }
      .coordinateSpace(name: "historyScroll")
      .scrollIndicators(.hidden)
      .onPreferenceChange(HistoryBottomPosition.self) { bottomY = $0 }
      .task(id: pagination(viewportHeight: viewport.size.height)) {
        // Let the appended page settle before deciding whether the viewport still needs filling.
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled, pagination(viewportHeight: viewport.size.height).shouldLoadMore else { return }
        manager.loadMoreConversations()
      }
    }
  }

  private func projectHeader(_ group: HistoryProviderGroup) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      if group.id != groups.first?.id {
        Rectangle().fill(theme.textColor.opacity(0.1)).frame(height: 0.5)
          .padding(.horizontal, 12)
      }
      HStack(spacing: 8) {
        ComposerFolderIcon().frame(width: 16, height: 16)
        Text(group.name).font(.system(size: 13, weight: .medium))
          .lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 0)
      }
      .foregroundStyle(theme.textColor.opacity(0.82))
      .padding(.horizontal, 12)
    }
    .padding(.top, group.id == groups.first?.id ? 8 : 12)
    .padding(.bottom, 4)
    .help(group.workspacePath ?? group.name)
  }

  private func pagination(viewportHeight: CGFloat) -> HistoryPaginationState {
    HistoryPaginationState(bottomY: bottomY, viewportHeight: viewportHeight, count: manager.conversations.count,
      hasMore: manager.hasMoreConversations, isLoading: manager.isLoadingMoreConversations,
      isConnected: manager.isConnected, isSearching: isSearching, isPresented: isPresented)
  }
}

private struct HistoryBottomPosition: PreferenceKey {
  static let defaultValue: CGFloat = .infinity
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = min(value, nextValue()) }
}
