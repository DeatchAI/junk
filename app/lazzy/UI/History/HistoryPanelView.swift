import Combine
import SwiftUI

struct HistoryPanelView: View {
  @ObservedObject var wsManager: WebSocketManager
  @ObservedObject var controller: HistoryWindowController
  @ObservedObject private var history: ProviderHistoryState
  @ObservedObject private var theme = ThemeManager.shared
  var onSelectConversation: (Conversation) -> Void
  var onClose: () -> Void

  @State private var searchText = ""
  @State private var isLoading = true

  init(wsManager: WebSocketManager, controller: HistoryWindowController,
    onSelectConversation: @escaping (Conversation) -> Void,
    onClose: @escaping () -> Void) {
    self.wsManager = wsManager; self.controller = controller; self.history = wsManager.providerHistory
    self.onSelectConversation = onSelectConversation; self.onClose = onClose
  }

  private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  private var providerGroups: [HistoryProviderGroup] {
    HistoryProviderGroup.groups(isSearching ? history.results : wsManager.conversations, by: .workingDirectory)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      searchBar
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .modifier(HistoryPanelSurface(placement: controller.placement))
    .clipShape(ScreenEdgeNotchShape(placement: controller.placement))
    .contentShape(ScreenEdgeNotchShape(placement: controller.placement))
    .preferredColorScheme(theme.surfaceColorScheme)
    .tint(theme.textColor)
    .onChange(of: searchText) { _, text in history.search(text, using: wsManager) }
    .onExitCommand(perform: onClose)
    .onReceive(wsManager.$conversations.dropFirst()) { _ in isLoading = false }
    .onChange(of: wsManager.isConnected) { _, connected in
      if connected {
        wsManager.refreshHistoryListing()
        if isSearching { history.search(searchText, using: wsManager) }
      }
    }
    .task {
      isLoading = wsManager.conversations.isEmpty && wsManager.isConnected
      wsManager.refreshHistoryListing()
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      isLoading = false
    }
  }

  private var searchBar: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12))
        .foregroundStyle(theme.secondaryTextColor)
      TextField(
        "Search chats and messages", text: $searchText,
        prompt: Text("Search").foregroundColor(theme.textColor.opacity(0.45))
      )
      .textFieldStyle(.plain)
      .font(.appFont(size: 12))
      .foregroundStyle(theme.textColor)
      .accessibilityLabel("Search all provider chats and messages")
      if !searchText.isEmpty {
        Button { searchText = "" } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(theme.secondaryTextColor)
        }
        .buttonStyle(.plain)
        .help("Clear search")
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 11)
    .background(theme.mode == .liquidGlass ? theme.controlBackgroundColor : theme.textColor.opacity(0.045), in: Capsule())
    .overlay { Capsule().strokeBorder(theme.textColor.opacity(0.07), lineWidth: 0.5).allowsHitTesting(false) }
    .padding(.horizontal, 8)
    .padding(.top, 4)
  }

  @ViewBuilder
  private var content: some View {
    if isLoading || (isSearching && history.isSearching && history.results.isEmpty) {
      VStack(spacing: 12) {
        AppSpinner()
        Text(isSearching ? "Searching histories…" : "Finding your conversations…")
          .font(.appFont(size: 12))
          .foregroundStyle(theme.secondaryTextColor)
      }
    } else if wsManager.conversations.isEmpty && !isSearching {
      emptyState(
        icon: "clock.arrow.circlepath", title: "Your agents, together",
        subtitle: history.error ?? "Saved provider chats appear here automatically."
      )
    } else if providerGroups.isEmpty {
      emptyState(
        icon: "magnifyingglass", title: "No matching conversations",
        subtitle: history.isIndexing ? "Message content is still being indexed. Results will update automatically." : "Try a title, project, or phrase from a message."
      )
    } else {
      HistoryChatList(manager: wsManager, groups: providerGroups, isSearching: isSearching,
        isPresented: controller.isVisible, onSelect: onSelectConversation)
    }
  }

  private func emptyState(icon: String, title: String, subtitle: String) -> some View {
    VStack(spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(theme.textColor.opacity(0.3))
      Text(title)
        .font(.appFont(size: 13, weight: .medium))
        .foregroundStyle(theme.textColor.opacity(0.8))
      Text(subtitle)
        .font(.appFont(size: 11))
        .foregroundStyle(theme.secondaryTextColor)
    }
    .multilineTextAlignment(.center)
    .padding(20)
  }
}
