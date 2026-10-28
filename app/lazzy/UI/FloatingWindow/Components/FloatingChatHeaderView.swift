import SwiftUI

/// The detached strip is exclusively navigation through sent exchanges.
struct FloatingChatHeaderView: View {
  let messages: [ChatMessage]
  @Binding var activeMessageIndex: Int?
  @Binding var lastCompletedResponse: String
  var canRevise = true
  var onRevise: (Int) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
            ComposerFollowUpChip(message: message, number: index + 1,
              isSelected: (activeMessageIndex ?? messages.count - 1) == index,
              canRevise: canRevise,
              onSelect: {
                activeMessageIndex = index
                lastCompletedResponse = message.aiResponse ?? ""
              }, onRevise: { onRevise(index) })
              .id(message.id)
          }
        }
        .padding(.vertical, 3)
      }
      .onChange(of: messages.count) { _, _ in
        if let id = messages.last?.id { proxy.scrollTo(id, anchor: .trailing) }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}
