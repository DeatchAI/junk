import AppKit
import SwiftUI

struct FloatingChatHeaderView: View {
  let sessionContexts: [DetectedContent]
  let messages: [ChatMessage]
  @Binding var activeMessageIndex: Int?
  @Binding var lastCompletedResponse: String
  @Binding var activeMediaJob: MediaJob?

  // Internal state for hover effects
  @State private var hoveredContent: String?

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(Array(sessionContexts.enumerated()), id: \.offset) { index, ctx in
          GlassChip(
            text: "\(index + 1)",
            icon: "doc.text.fill", isSelected: true,
            action: {
              copyToClipboard(ctx.text ?? "File Content")
            }
          )
          .onHover { isHovering in
            handleHover(isHovering, content: ctx.text ?? "File Content")
          }
        }

        ForEach(Array(messages.enumerated()), id: \.offset) { index, msg in
          let isSelected =
            (activeMessageIndex == nil && index == messages.count - 1)
            || (activeMessageIndex == index)
          GlassChip(
            text: "\(index + 1)", icon: nil,
            isSelected: isSelected,
            action: {
              activeMessageIndex = index
              lastCompletedResponse = msg.aiResponse ?? ""
              activeMediaJob = msg.mediaJob
              copyToClipboard(msg.userPrompt)
            }
          )
          .onHover { isHovering in
            handleHover(isHovering, content: msg.userPrompt)
          }
        }
      }
      .padding(.top, 50)
      .padding(.bottom, 8)
    }
    .overlay(alignment: .bottomLeading) {
      if let text = hoveredContent {
        TooltipView(text: text)
          .offset(y: -50)  // Positioned above the chips
          .padding(.leading, 12)
          .transition(
            .asymmetric(
              insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .bottom)).combined(
                with: .move(edge: .bottom)),
              removal: .opacity.combined(with: .scale(scale: 0.95))
            )
          )
      }
    }
  }

  // MARK: - Helper Methods

  private func cleanMarkerContent(_ content: String) -> String {
    var displayContent = content
    if let range = displayContent.range(of: "\"User Message:\"\n") {
      displayContent = String(displayContent[range.upperBound...])
    }
    displayContent = displayContent.replacingOccurrences(of: "\"User Context:\"\n", with: "")
    return displayContent.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func copyToClipboard(_ content: String) {
    let displayContent = cleanMarkerContent(content)
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(displayContent, forType: .string)
    print("📋 Copied to clipboard: \(displayContent.prefix(50))...")
  }

  private func handleHover(_ isHovering: Bool, content: String) {
    let displayContent = cleanMarkerContent(content)

    // Standard spring for enterprise feels
    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
      if isHovering {
        hoveredContent = displayContent
        NSCursor.pointingHand.push()
      } else {
        hoveredContent = nil
        NSCursor.pop()
      }
    }
  }
}

// MARK: - Subcomponents

struct TooltipView: View {
  let text: String
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Text(text)
      .font(.appFont(size: 11, weight: .medium))
      .foregroundStyle(theme.textColor)
      .lineLimit(2)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(
        Group {
          RoundedRectangle(cornerRadius: theme.borderRadius)
            .fill(.ultraThinMaterial)

          RoundedRectangle(cornerRadius: theme.borderRadius)
            .fill(theme.backgroundColor)
        }
      )
      .frame(maxWidth: 280, alignment: .leading)
      .compositingGroup()
  }
}

struct GlassChip: View {
  let text: String
  let icon: String?
  let isSelected: Bool
  var action: (() -> Void)? = nil

  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    Button(action: { action?() }) {
      HStack(spacing: 4) {
        if let icon = icon {
          Image(systemName: icon)
            .font(.appFont(size: 10))
        }
        Text(text)
          .font(.appFont(size: 11, weight: .medium))
      }
      .foregroundStyle(theme.textColor)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(
        Group {
          RoundedRectangle(cornerRadius: theme.borderRadius)
            .fill(.ultraThinMaterial)

          RoundedRectangle(cornerRadius: theme.borderRadius)
            .fill(theme.backgroundColor)
        }
      )
    }
    .buttonStyle(.plain)
  }
}
