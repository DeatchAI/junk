import AppKit
import SwiftUI

struct FloatingChatResponseView: View {
  let streamingResponse: String
  let lastCompletedResponse: String
  var completedParts: [MessagePart] = []
  let responseEvents: [AgentResponseEvent]
  let isThinking: Bool
  let errorMessage: String?
  let currentActivity: String
  var maxStreamingHeight: CGFloat
  var canBranchResponse = false
  var onBranchResponse: (() -> Void)? = nil
  var gitMessage: ChatMessage? = nil
  var gitWorkspace: String? = nil
  var gitConversationID: String? = nil
  var gitEndpoint: RuntimeEndpoint = .local

  // Internal state for content height
  @State private var contentHeight: CGFloat = 54
  @ObservedObject private var theme = ThemeManager.shared

  // PreferenceKey to read height dynamically
  private struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      value = max(value, nextValue())
    }
  }

  // Custom blur transition
  private struct BlurModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View {
      content
        .blur(radius: radius)
        .opacity(opacity)
    }
  }

  private var blurTransition: AnyTransition {
    .modifier(
      active: BlurModifier(radius: 8, opacity: 0),
      identity: BlurModifier(radius: 0, opacity: 1)
    )
  }

  var body: some View {
    // Show streaming response if available, otherwise show the last completed response
    let displayText: String = {
      if !streamingResponse.isEmpty {
        return streamingResponse
      } else if !lastCompletedResponse.isEmpty {
        return lastCompletedResponse
      }
      return ""  // Thinking state handled below
    }()

    let isLive = isThinking || !streamingResponse.isEmpty
    let hasTimeline = !responseEvents.isEmpty
    // Activity events are useful while an agent is working, but must never
    // replace the completed assistant response. Otherwise a finished run can
    // appear to jump to an arbitrary status line instead of its first text.
    let showTimeline = hasTimeline && (isLive || displayText.isEmpty)
    let hasActivity = responseEvents.contains { $0.kind == .activity }
    let shouldShowLiveActivityHeader =
      isLive && !currentActivity.isEmpty && !hasActivity

    let showActions = !isLive && (!displayText.isEmpty || gitMessage != nil)
    let actionBarHeight: CGFloat = showActions ? 52 : 0
    let responseHeight = min(max(contentHeight, 0), max(maxStreamingHeight - actionBarHeight, 0))

    return VStack(spacing: 0) {
      ScrollView(.vertical, showsIndicators: true) {
        responseContent(
          displayText: displayText,
          showTimeline: showTimeline,
          shouldShowLiveActivityHeader: shouldShowLiveActivityHeader
        )
      }
      .frame(height: responseHeight)
      .background(Color.clear)

      if showActions {
        HStack(spacing: 12) {
          if !displayText.isEmpty {
            ResponseActionButtons(text: ChatTranscript.readableText(ChatTranscript.parts(text: displayText, structured: completedParts)),
              responseID: gitMessage?.id.uuidString ?? gitConversationID ?? "response",
              canBranch: canBranchResponse, onBranch: onBranchResponse)
          }
          Spacer(minLength: 0)
          if let message = gitMessage {
            GitTaskChangeCard(workspace: gitWorkspace, runID: message.gitRunID, conversationID: gitConversationID,
              prompt: message.userPrompt, timestamp: message.gitTimestamp, ordinal: message.gitMessageOrdinal,
              revision: message.gitRevision, endpoint: gitEndpoint)
          }
        }
        .frame(minHeight: 32)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
      }
    }
    .onPreferenceChange(ViewHeightKey.self) { height in
      guard abs(contentHeight - height) >= 0.5 else { return }
      DispatchQueue.main.async {
        contentHeight = height
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func responseContent(
    displayText: String,
    showTimeline: Bool,
    shouldShowLiveActivityHeader: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if let error = errorMessage {
        HStack(spacing: 6) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.appFont(size: 12))
          Text(error)
            .font(.appFont(size: 12))
        }
        .foregroundColor(.red)
        .padding(12)
        .transition(
          .asymmetric(
            insertion: blurTransition.combined(with: .scale(scale: 0.95)),
            removal: .opacity
          ))
      } else {
        VStack(alignment: .leading, spacing: 12) {
          if shouldShowLiveActivityHeader {
            AgentActivityText(activity: currentActivity, fontSize: 12)
              .padding(.horizontal, 18)
              .padding(.top, 16)
              .padding(.bottom, showTimeline ? 0 : 16)
          }

          if showTimeline {
            ResponseTimelineView(events: responseEvents, compact: true)
              .padding(.horizontal, 18)
              .padding(.top, shouldShowLiveActivityHeader ? 0 : 16)
              .padding(.bottom, 16)
          } else {
            ChatTranscriptView(parts: ChatTranscript.parts(text: displayText, structured: completedParts))
              .padding(.horizontal, 18)
              .padding(.top, 16)
              .padding(.bottom, 16)
              .transition(
                .asymmetric(
                  insertion: blurTransition.combined(with: .scale(scale: 0.98)),
                  removal: .opacity
                ))
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      GeometryReader { geo in
        Color.clear
          .preference(key: ViewHeightKey.self, value: geo.size.height)
      }
    )
  }
}

struct ResponseTimelineView: View {
  let events: [AgentResponseEvent]
  var compact: Bool = false

  var body: some View {
    ChatTranscriptView(parts: events.map(\.messagePart))
  }
}
