import AppKit
import Combine
import Foundation
import SwiftUI

/// Controller for the history side panel window - appears on the left edge of screen
@MainActor
class HistoryWindowController: NSObject, ObservableObject {

  private var historyWindow: NSPanel?
  @Published private(set) var isVisible = false

  // WebSocket manager reference
  weak var wsManager: WebSocketManager?

  // Callbacks
  var onSelectConversation: ((Conversation) -> Void)?
  var onNewConversation: (() -> Void)?

  override init() {
    super.init()
  }

  // MARK: - Show/Hide

  /// Show the history panel on the left side of the screen
  func show() {
    if historyWindow == nil {
      createHistoryWindow()
    }

    guard let screen = NSScreen.main else { return }
    let screenFrame = screen.visibleFrame

    // 30% of screen width, full height (minus margins), positioned at left edge with margin
    let panelWidth = screenFrame.width * 0.3
    let margin: CGFloat = 16
    let frame = NSRect(
      x: screenFrame.minX + margin,
      y: screenFrame.minY + margin,
      width: panelWidth,
      height: screenFrame.height - (margin * 2)
    )

    historyWindow?.setFrame(frame, display: true)
    historyWindow?.makeKeyAndOrderFront(nil)

    // Animate in from left
    historyWindow?.alphaValue = 0
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      historyWindow?.animator().alphaValue = 1
    }

    isVisible = true
    print("📚 History panel shown")
  }

  /// Hide the history panel with animation
  func hide() {
    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = 0.2
        context.timingFunction = CAMediaTimingFunction(name: .easeIn)
        historyWindow?.animator().alphaValue = 0
      },
      completionHandler: { [weak self] in
        Task { @MainActor [weak self] in
          self?.historyWindow?.orderOut(nil)
        }
      })

    isVisible = false
    print("📚 History panel hidden")
  }

  /// Toggle visibility
  func toggle() {
    if isVisible {
      hide()
    } else {
      show()
    }
  }

  // MARK: - Window Creation

  private func createHistoryWindow() {
    guard let screen = NSScreen.main else { return }
    let screenFrame = screen.visibleFrame
    let panelWidth = screenFrame.width * 0.2
    let margin: CGFloat = 16

    let panel = KeyablePanel(
      contentRect: NSRect(
        x: screenFrame.minX,
        y: screenFrame.minY + margin,
        width: panelWidth,
        height: screenFrame.height - (margin * 2)
      ),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.isMovableByWindowBackground = false  // Fixed position
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true

    // Create the history view
    let historyView = HistoryPanelView(
      wsManager: wsManager ?? WebSocketManager(),
      onSelectConversation: { [weak self] conv in
        self?.onSelectConversation?(conv)
        self?.hide()
      },
      onNewConversation: { [weak self] in
        self?.onNewConversation?()
        self?.hide()
      },
      onClose: { [weak self] in
        self?.hide()
      }
    )

    let hostingView = NSHostingView(
      rootView: historyView.font(.custom("Geist-Regular", size: 13)))
    panel.contentView = hostingView

    historyWindow = panel
  }

  /// Force refresh the panel content
  func refresh() {
    if isVisible {
      historyWindow?.close()
      historyWindow = nil
      show()
    }
  }
}

// MARK: - Full Height History Panel View

struct HistoryPanelView: View {
  @ObservedObject var wsManager: WebSocketManager
  var onSelectConversation: (Conversation) -> Void
  var onNewConversation: () -> Void
  var onClose: () -> Void

  @State private var searchText = ""
  @State private var isLoading = true

  // Theme manager
  @ObservedObject private var theme = ThemeManager.shared

  private var filteredConversations: [Conversation] {
    if searchText.isEmpty {
      return wsManager.conversations
    }
    return wsManager.conversations.filter { conv in
      let title = conv.title ?? "Untitled"
      return title.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      headerView

      // Search bar
      searchBar

      // Conversation list or empty state
      if isLoading {
        loadingState
      } else if wsManager.conversations.isEmpty {
        emptyState
      } else if filteredConversations.isEmpty {
        noResultsState
      } else {
        conversationList
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.backgroundFill)
    .clipShape(RoundedRectangle(cornerRadius: theme.borderRadius))
    // .overlay(
    //   RoundedRectangle(cornerRadius: theme.borderRadius)
    //     .stroke(theme.borderColor, lineWidth: 0.5)
    // )
    .onAppear {
      loadConversations()
    }
  }

  // MARK: - Header

  private var headerView: some View {
    HStack {
      //   Text("Conversation History")
      //     .font(.appFont(size: 16, weight: .semibold))
      //     .foregroundColor(theme.textColor)
      Button(action: onNewConversation) {
        HStack(spacing: 4) {
          Image(systemName: "plus")
            .font(.appFont(size: 15, weight: .medium))
          Text("New Chat")
            .font(.appFont(size: 15, weight: .medium))
        }
        .foregroundColor(theme.textColor)
        .padding(.horizontal, 10 + theme.borderRadius / 1.5)
        .padding(.vertical, 6 + theme.borderRadius / 5)
      }
      .buttonStyle(.plain)
      .background(theme.accentColor)
      .cornerRadius(theme.borderRadius / 1.5)

      Spacer()

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.appFont(size: 15, weight: .medium))
          .foregroundColor(theme.accentColor)
      }
      .buttonStyle(.plain)
    }
    .padding(.horizontal, 10 + theme.borderRadius / 1.5)
    .padding(.vertical, 16 + theme.borderRadius / 5)
    // .background(theme.backgroundColor)
  }

  // MARK: - Search Bar

  private var searchBar: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.appFont(size: 14))
        .foregroundColor(theme.secondaryTextColor)

      TextField("", text: $searchText)
        .placeholder(when: searchText.isEmpty) {
          Text("Search conversations...").foregroundColor(theme.secondaryTextColor)
        }
        .textFieldStyle(.plain)
        .font(.appFont(size: 14))
        .foregroundColor(theme.secondaryTextColor)
    }
    // .background(theme.inputBackgroundColor)
    .cornerRadius(theme.borderRadius / 1.5)
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .border(theme.borderColor, width: 0.5)
  }

  // MARK: - Conversation List

  private var conversationList: some View {
    ScrollView {
      LazyVStack(spacing: 4) {
        ForEach(filteredConversations) { conv in
          HistoryRowView(
            conversation: conv,
            isSelected: wsManager.currentConversationId == conv.id,
            onSelect: {
              onSelectConversation(conv)
            },
            onDelete: {
              wsManager.deleteConversation(id: conv.id)
            }
          )
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
    }
  }

  // MARK: - Empty States

  private var loadingState: some View {
    VStack(spacing: 16) {
      ProgressView()
        .scaleEffect(1.0)
        .colorInvert()
      Text("Loading conversations...")
        .font(.appFont(size: 14))
        .foregroundColor(theme.secondaryTextColor)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "clock.arrow.circlepath")
        .font(.appFont(size: 48))
        .foregroundColor(theme.secondaryTextColor.opacity(0.5))

      Text("No conversations yet")
        .font(.appFont(size: 16, weight: .medium))
        .foregroundColor(theme.secondaryTextColor)

      Text("Start chatting to see your history here")
        .font(.appFont(size: 13))
        .foregroundColor(theme.secondaryTextColor.opacity(0.7))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
  }

  private var noResultsState: some View {
    VStack(spacing: 16) {
      Image(systemName: "magnifyingglass")
        .font(.appFont(size: 32))
        .foregroundColor(theme.secondaryTextColor.opacity(0.5))

      Text("No results for \"\(searchText)\"")
        .font(.appFont(size: 14))
        .foregroundColor(theme.secondaryTextColor)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Actions

  private func loadConversations() {
    isLoading = true
    wsManager.listConversations()

    wsManager.onConversationsLoaded = { _ in
      isLoading = false
    }

    // Timeout fallback
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
      isLoading = false
    }
  }
}

// MARK: - History Row View

struct HistoryRowView: View {
  let conversation: Conversation
  let isSelected: Bool
  var onSelect: () -> Void
  var onDelete: () -> Void

  @State private var isHovered = false
  @ObservedObject private var theme = ThemeManager.shared

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(conversation.title ?? "New Chat")
          .font(.appFont(size: 13, weight: isSelected ? .semibold : .regular))
          .foregroundColor(isSelected ? .white : theme.textColor)
          .lineLimit(1)

        Text(relativeDate(from: conversation.updatedDate))
          .font(.appFont(size: 10))
          .foregroundColor(isSelected ? .white.opacity(0.8) : theme.secondaryTextColor)
      }

      Spacer()

      if isHovered || isSelected {
        Button(action: onDelete) {
          Image(systemName: "trash")
            .font(.appFont(size: 11))
            .foregroundColor(isSelected ? .white : theme.accentColor)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .contentShape(Rectangle())  // Makes the whole row clickable
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(rowBackground)
    )
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering }
    }
    .onTapGesture { onSelect() }
  }

  private var rowBackground: Color {
    if isSelected { return theme.accentColor }
    if isHovered { return Color.primary.opacity(0.06) }  // Light ghost gray
    return Color.clear
  }

  private func relativeDate(from date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: date, relativeTo: Date())
  }
}
