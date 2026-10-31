import AppKit
import SwiftUI

struct FloatingChatExpandedView: View {
  let messages: [ChatMessage]
  let isThinking: Bool
  let streamingResponse: String
  let currentActivity: String
  let responseEvents: [AgentResponseEvent]
  var canRevise = true
  var onRevise: ((Int) -> Void)? = nil
  var onBranch: ((Int) -> Void)? = nil
  var gitWorkspace: String? = nil
  var gitConversationID: String? = nil
  var gitEndpoint: RuntimeEndpoint = .local

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
          ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
            // User Message
            HStack {
              Spacer(minLength: 0)
              VStack(alignment: .leading, spacing: 8) {
                if !msg.attachments.isEmpty {
                  ComposerAttachmentList(attachments: msg.attachments)
                }
                Text(cleanMarkerContent(msg.userPrompt))
                if let onRevise {
                  HStack {
                    Spacer()
                    Button { onRevise(index) } label: {
                      Image(systemName: "pencil").font(.system(size: 11))
                        .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain).disabled(!canRevise || msg.branchReference?.canBranch != true)
                    .foregroundStyle(theme.secondaryTextColor)
                    .help("Edit message in a new branch")
                    .accessibilityLabel("Edit message \(index + 1)")
                  }
                }
              }
                .font(.appFont(size: 14))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(theme.textColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.textColor.opacity(0.06))
                .cornerRadius(12)
            }
            .padding(.leading, 40)

            // AI Response
            if let response = msg.aiResponse {
              HStack(alignment: .top, spacing: 12) {
                // AI Icon/Avatar could go here
                VStack(alignment: .leading, spacing: 10) {
                  ChatTranscriptView(parts: ChatTranscript.parts(text: response, structured: msg.responseParts))
                    .padding(.horizontal, 4)
                  ResponseActionButtons(text: ChatTranscript.readableText(ChatTranscript.parts(text: response, structured: msg.responseParts)),
                    responseID: msg.id.uuidString, canBranch: canRevise && msg.branchReference?.canBranchAfter == true,
                    onBranch: onBranch.map { callback in { callback(index) } })
                }
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
          }

          if !isThinking, streamingResponse.isEmpty, let msg = messages.last {
            GitTaskChangeCard(workspace: gitWorkspace, runID: msg.gitRunID, conversationID: gitConversationID,
              prompt: msg.userPrompt, timestamp: msg.gitTimestamp, ordinal: msg.gitMessageOrdinal,
              revision: msg.gitRevision, endpoint: gitEndpoint)
          }

          Color.clear.frame(height: 1).id("bottom")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
      }
      .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
      .clipped()
      .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
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
    return ConversationPrompt.readable(displayContent)
  }
}
