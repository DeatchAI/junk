import AppKit
import SwiftUI

struct FloatingChatExpandedView: View {
  let messages: [ChatMessage]
  let isThinking: Bool
  let streamingResponse: String
  let currentActivity: String
  let responseEvents: [AgentResponseEvent]

  @ObservedObject private var theme = ThemeManager.shared

  private var hasActivity: Bool {
    responseEvents.contains { $0.kind == .activity }
  }

  private var shouldShowLiveActivityHeader: Bool {
    (isThinking || !streamingResponse.isEmpty)
      && !currentActivity.isEmpty
      && !hasActivity
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          ForEach(messages) { msg in
            // User Message
            HStack {
              Spacer()
              Text(cleanMarkerContent(msg.userPrompt))
                .font(.appFont(size: 14))
                .foregroundColor(theme.textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.accentColor.opacity(0.15))
                .cornerRadius(12)
            }
            .padding(.leading, 40)

            // AI Response
            if let response = msg.aiResponse {
              HStack(alignment: .top, spacing: 12) {
                // AI Icon/Avatar could go here
                MarkdownMessageView(text: response)
                  .padding(.horizontal, 4)
              }
              .padding(.trailing, 20)
            }
          }

          // Current Streaming / Thinking
          if !streamingResponse.isEmpty || !responseEvents.isEmpty
            || (isThinking && !currentActivity.isEmpty)
          {
            HStack(alignment: .top, spacing: 12) {
              VStack(alignment: .leading, spacing: 12) {
                if shouldShowLiveActivityHeader {
                  AgentActivityText(activity: currentActivity, fontSize: 12)
                }

                if !responseEvents.isEmpty {
                  ResponseTimelineView(events: responseEvents)
                } else if !streamingResponse.isEmpty {
                  MarkdownMessageView(text: streamingResponse)
                }
              }
            }
            .padding(.trailing, 20)
            .id("bottom")
          }

          Spacer().frame(height: 20)
        }
        .padding(20)
      }
      .onChange(of: streamingResponse) { _, _ in
        if !streamingResponse.isEmpty {
          proxy.scrollTo("bottom", anchor: .bottom)
        }
      }
      .onChange(of: messages.count) { _, _ in
        proxy.scrollTo("bottom", anchor: .bottom)
      }
    }
  }

  private func cleanMarkerContent(_ content: String) -> String {
    var displayContent = content
    if let range = displayContent.range(of: "\"User Message:\"\n") {
      displayContent = String(displayContent[range.upperBound...])
    }
    displayContent = displayContent.replacingOccurrences(of: "\"User Context:\"\n", with: "")
    return displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
