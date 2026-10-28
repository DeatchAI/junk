import SwiftUI

struct ProviderConversationNotice: View {
  let conversation: Conversation?
  var onNewChat: () -> Void
  private var text: String? {
    guard let conversation else { return nil }
    if conversation.isLegacy { return "Preserved Detach chat. Replying starts a new provider session; this archive stays unchanged." }
    return conversation.historyWarning ?? (conversation.canResume == false ? "This chat is available as history only." : nil)
  }
  var body: some View {
    if let text {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "info.circle")
        Text(text).fixedSize(horizontal: false, vertical: true)
        if conversation?.canResume == false && conversation?.isProviderHistory == true {
          Button("New chat", action: onNewChat).buttonStyle(.plain).underline()
        }
      }.font(.appFont(size: 10)).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
  }
}
