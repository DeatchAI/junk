import SwiftUI

struct ComposerConversationsMenu: View {
  @Binding var page: ComposerAttachmentMenuPage
  @ObservedObject var store: ComposerConversationStore
  let conversations: [Conversation]
  let selectedIDs: Set<String>
  @Binding var selectedIndex: Int
  let onAttach: (Conversation) -> Void
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      ComposerAttachmentMenuHeader(title: "Past conversations") { page = .root }
      Text(store.query.isEmpty ? "Type after @ to search conversations" : "Results for “\(store.query)”")
        .font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor)
        .lineLimit(1).padding(.horizontal, 10).padding(.bottom, 4)

      if conversations.isEmpty && store.isLoading {
        ProgressView("Loading conversations…").controlSize(.small)
          .font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 72)
      } else if conversations.isEmpty && store.error == nil {
        ComposerAttachmentMenuEmptyState(text: store.query.isEmpty ? "No past conversations yet" : "No conversations found")
      }

      if !conversations.isEmpty || store.hasMore {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(Array(conversations.enumerated()), id: \.element.id) { index, conversation in
                row(conversation, index: index).id(conversation.id)
              }
              if store.hasMore {
                Button(action: store.loadMore) {
                  HStack(spacing: 6) {
                    if store.isLoading { ProgressView().controlSize(.mini) }
                    Text(store.isLoading ? "Loading…" : "Show more")
                  }.font(.system(size: 12)).frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.plain).disabled(store.isLoading || store.isAttaching)
                .foregroundStyle(theme.secondaryTextColor)
              }
            }
          }
          .frame(maxHeight: 230)
          .onChange(of: selectedIndex) { _, index in
            if conversations.indices.contains(index) { proxy.scrollTo(conversations[index].id) }
          }
        }
      }

      if let error = store.error {
        VStack(alignment: .leading, spacing: 6) {
          Text(error).font(.system(size: 11)).lineLimit(3)
          if conversations.isEmpty {
            Button("Retry") { store.search(store.query, immediately: true) }
              .font(.system(size: 12, weight: .medium)).buttonStyle(.plain)
          }
        }
        .foregroundStyle(theme.secondaryTextColor).padding(10)
      }
    }
    .foregroundStyle(theme.textColor)
  }

  private func row(_ conversation: Conversation, index: Int) -> some View {
    let title = conversation.title?.trimmingCharacters(in: .whitespacesAndNewlines)
    let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled conversation"
    let provider = conversation.provider.map(AgentProvider.displayName(for:)) ?? "Detach"
    let isSelected = selectedIDs.contains(conversation.id)
    return Button { onAttach(conversation) } label: {
      HStack(spacing: 8) {
        Image(systemName: "bubble.left").font(.system(size: 13)).frame(width: 16)
        Text(name).font(.system(size: 13, weight: .regular)).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        if store.attachingID == conversation.id {
          ProgressView().controlSize(.mini).accessibilityLabel("Attaching conversation")
        } else if isSelected {
          Image(systemName: "checkmark").font(.system(size: 11, weight: .medium))
        } else {
          Text(provider).font(.system(size: 11)).foregroundStyle(theme.secondaryTextColor).lineLimit(1)
        }
      }
      .padding(.horizontal, 7).frame(height: ComposerMenuStyle.rowHeight)
      .contentShape(Rectangle())
      .background(theme.textColor.opacity(selectedIndex == index ? 0.065 : 0),
        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain).disabled(store.isAttaching || isSelected)
    .onHover { if $0 { selectedIndex = index } }
    .help("\(name) · \(provider)\(conversation.workspacePath.map { " · \($0)" } ?? "")")
    .accessibilityLabel("\(name), \(provider) conversation\(isSelected ? ", attached" : "")")
  }
}
