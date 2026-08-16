import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// The floating chat interface - minimal dark design
struct FloatingChatView: View {
  @ObservedObject var controller: FloatingWindowController
  @ObservedObject var wsManager: WebSocketManager
  var onClose: () -> Void
  var onToggleHistory: (() -> Void)?
  var onHistoryRefresh: (() -> Void)?
  var onNewChat: (() -> Void)?

  @State var sessionContexts: [DetectedContent] = []  // Accumulated contexts for this session
  @State var pendingAttachments: [ChatAttachment] = []  // Files to attach to next message
  @State var pendingSkills: [SkillAttachment] = []
  @State var pendingBrowserTabs: [BrowserTabAttachment] = []
  @State var pendingMCPAttachments: [ComposerMCPAttachment] = []
  @State var pendingCommandAliases: [SlashCommandAlias] = []
  @StateObject var skillsDirectory = SkillsDirectoryService()
  @StateObject var browserTabStore = BrowserTabStore()
  @StateObject var workingDirectoryStore = WorkingDirectoryStore()
  @State var isInlineAttachmentMenuRequested = false
  @State var isInlineAttachmentMenuActive = false
  @State var isInlineCommandMenuActive = false
  @State var debugMenuStep: DebugComposerMenuStep?

  @State var inputText = ""
  @State var messages: [ChatMessage] = []  // All chat exchanges
  @State var streamingResponse = ""  // Current streaming AI response
  @State var lastCompletedResponse = ""  // Keeps the last response visible after streaming ends
  @State var responseEvents: [AgentResponseEvent] = []
  @State var isThinking = false  // Shows loading state before first chunk arrives
  @State var activeMessageIndex: Int? = nil  // Index of the message currently being viewed
  @State var selectedMode = "Auto"
  @State var outputMode: ComposerOutputMode = .agent
  @State var selectedMediaModelID = ""
  @State var mediaConfig = MediaGenerationConfig()
  @State var mediaQuote: MediaQuote?
  @State var mediaQuoteRequestID = ""
  @State var latestMediaJob: MediaJob?
  @State var isMediaDropTargeted = false
  @State var fastMode = false  // Fast mode toggle
  @FocusState var isInputFocused: Bool
  @State var shortcutMonitor: Any?
  @State var debugDemoTypingTask: Task<Void, Never>?

  // Stats tracking
  @State var timeToFirstChunk: Int? = nil  // ms
  @State var lastTokenCount: Int? = nil
  @State var lastDurationMs: Int? = nil
  @State var requestStartTime: Date? = nil  // For live timer
  @State var currentActivity: String = "Thinking..."  // Dynamic AI activity status
  @State var errorMessage: String? = nil  // Error message state

  // Theme manager reference
  @ObservedObject var theme = ThemeManager.shared

  var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 12) {
        if controller.isExpanded {
          expandedSection
        } else {
          if hasConversationNavigation {
            FloatingChatHeaderView(
              sessionContexts: sessionContexts,
              messages: messages,
              activeMessageIndex: $activeMessageIndex,
              lastCompletedResponse: $lastCompletedResponse,
              activeMediaJob: $latestMediaJob,
              pendingAttachments: pendingAttachments,
              onRemoveAttachment: removeAttachment
            )
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .zIndex(2)
          }
        }

        if !controller.isExpanded
          && (!streamingResponse.isEmpty || !lastCompletedResponse.isEmpty
            || !visibleResponseEvents.isEmpty || isThinking || errorMessage != nil
            || latestMediaJob != nil)
        {
          responseSection
        }

        VStack(spacing: 0) {
          inputAndToolbarSection
          WorkingDirectoryTray(store: workingDirectoryStore)
        }
      }
      .onAppear {
        setupWSManager()
        loadCurrentConversation()
        refreshComposerResources()
        // Add initial content if present
        if let content = controller.detectedContent {
          addContextIfNeeded(content)
        }
        isInputFocused = true
#if DEBUG
        controller.onDebugDemoKeyDown = { event, functionIsDown in
          guard !isInlineAttachmentMenuActive,
            !isInlineCommandMenuActive,
            let prompt = debugDemoPrompt(for: event, functionIsDown: functionIsDown)
          else {
            return false
          }
          startDebugDemoTyping(prompt)
          return true
        }
#endif
        setupShortcutMonitor()
      }
      .onDisappear {
        removeShortcutMonitor()
#if DEBUG
        controller.onDebugDemoKeyDown = nil
        debugDemoTypingTask?.cancel()
        debugMenuStep = nil
#endif
      }
      .onChange(of: controller.detectedContent) { _, newValue in
        if let content = newValue {
          addContextIfNeeded(content)
        }
      }
      .onChange(of: wsManager.isStreaming) { _, isStreaming in
        // Reset thinking state when streaming stops (e.g., user pressed stop)
        if !isStreaming {
          isThinking = false
        }
      }
      .onChange(of: outputMode) { _, _ in
        selectDefaultMediaModelIfNeeded()
        requestMediaQuote()
      }
      .onChange(of: selectedMediaModelID) { _, _ in
        if let model = selectedMediaModel {
          mediaConfig = model.defaults
        }
        requestMediaQuote()
      }
      .onChange(of: mediaConfig) { _, _ in
        requestMediaQuote()
      }
      .onChange(of: pendingAttachments) { _, _ in
        requestMediaQuote()
      }
    }
    .padding(.top, 15)  // Add top space for the detached button
    // Keep the conversation and composer centered within the borderless panel.
    // A trailing-only inset made the whole surface appear to drift left whenever
    // the response or composer changed its intrinsic width.
    .padding(.horizontal, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .onHover { controller.updateDebugPointerHover($0) }
    .onDrop(
      of: [UTType.fileURL, UTType.url, UTType.image, UTType.movie],
      isTargeted: $isMediaDropTargeted,
      perform: handleMediaDrop
    )
    .overlay(alignment: .top) {
      if isMediaDropTargeted {
        Text("Drop image or video")
          .font(.appFont(size: 11, weight: .semibold))
          .foregroundStyle(theme.textColor)
          .padding(.horizontal, 11)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial, in: Capsule())
          .overlay(Capsule().stroke(theme.accentColor.opacity(0.55), lineWidth: 1))
          .padding(.top, 8)
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
      }
    }
    .background(
      GeometryReader { geo in
        Color.clear
          .preference(key: WindowHeightKey.self, value: geo.size.height)
      }
    )
    .onPreferenceChange(WindowHeightKey.self) { height in
      controller.updateWindowHeight(height)
    }
    .onChange(of: controller.dictationInsertion) { _, insertion in
      guard let insertion else { return }
      appendVoiceTranscription(insertion.text)
    }
    // Keep the SwiftUI side of the borderless panel on the same fixed-width
    // contract as FloatingComposerPanel. Media players and images must fill
    // this proposal instead of shrinking the entire composer around their
    // intrinsic size.
    .frame(width: FloatingWindowController.compactWindowWidth, alignment: .leading)
  }

  @ViewBuilder
  private var expandedSection: some View {
    FloatingChatExpandedView(
      messages: messages,
      isThinking: isThinking,
      streamingResponse: streamingResponse,
      currentActivity: currentActivity,
      responseEvents: visibleResponseEvents
    )
    .background {
      Group {
        if theme.usesGlassEffect {
          ZStack {
            RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
              .fill(.ultraThinMaterial)
            if let overlay = theme.glassOverlay {
              RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
                .fill(overlay)
            }
          }
        } else {
          RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
            .fill(theme.solidBackground)
        }
      }
    }
  }

  @ViewBuilder
  private var responseSection: some View {
    FloatingChatResponseView(
      streamingResponse: streamingResponse,
      lastCompletedResponse: lastCompletedResponse,
      responseEvents: visibleResponseEvents,
      isThinking: isThinking,
      errorMessage: errorMessage,
      currentActivity: currentActivity,
      mediaJob: latestMediaJob,
      maxStreamingHeight: maxStreamingHeight
    )
    .background {
      Group {
        if theme.usesGlassEffect {
          ZStack {
            // 1. The Blur Layer
            RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
              .fill(.ultraThinMaterial)
            // 2. The Universal Tint Layer (The "Sweet Spot")
            if let overlay = theme.glassOverlay {
              RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
                .fill(overlay)
            }
          }
        } else {
          // Solid mode - no glass effect
          RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
            .fill(theme.solidBackground)
        }
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
        .stroke(theme.textColor.opacity(0.10), lineWidth: 0.7)
    }
    .transition(
      .asymmetric(
        insertion: blurTransition.combined(with: .scale(scale: 0.98)),
        removal: .opacity
      ))
  }

  @ViewBuilder
  private var inputAndToolbarSection: some View {
    VStack(spacing: 0) {
      // Main input area
      FloatingChatInputView(
        inputText: $inputText,
        debugMenuStep: $debugMenuStep,
        isInputFocused: $isInputFocused,
        onClose: onClose,
        onSubmit: sendMessage,
        onPasteAttachment: handlePaste,
        fileAttachments: pendingAttachments,
        selectedSkills: pendingSkills,
        selectedBrowserTabs: pendingBrowserTabs,
        selectedMCPAttachments: pendingMCPAttachments,
        selectedCommands: pendingCommandAliases,
        availableMCPAttachments: availableComposerMCPAttachments,
        isLoadingMCPAttachments: !wsManager.isConnected
          || wsManager.isLoadingMCPServers
          || (wsManager.isLoadingComposio && wsManager.composioIntegrations.isEmpty),
        availableSkills: skillsDirectory.installedSkills,
        workflows: wsManager.workflows,
        quickActions: wsManager.customQuickActions,
        isAttachmentMenuRequested: $isInlineAttachmentMenuRequested,
        isAttachmentMenuActive: $isInlineAttachmentMenuActive,
        isCommandMenuActive: $isInlineCommandMenuActive,
        skillsDirectory: skillsDirectory,
        workingDirectoryStore: workingDirectoryStore,
        browserTabStore: browserTabStore,
        onAttachFile: addFileAttachment,
        onAttachSkill: addSkillAttachment,
        onAttachBrowserTab: addBrowserTabAttachment,
        onRefreshBrowserTabs: browserTabStore.refresh,
        onAttachMCP: addMCPAttachment,
        onOpenMCPServers: {
          wsManager.listMCPServers()
          wsManager.listComposioIntegrations(limit: 100)
        },
        onAttachCommand: addCommandAlias,
        onCreateCommand: createInlineCommand,
        onRunCommandAction: runComposerCommandAction,
        onOpenCommandDestination: openComposerCommandDestination,
        onRemoveFile: removeAttachment,
        onRemoveSkill: removeSkillAttachment,
        onRemoveBrowserTab: removeBrowserTabAttachment,
        onRemoveMCP: removeMCPAttachment,
        onRemoveCommand: removeCommandAlias,
        voiceDictationState: controller.voiceDictationState,
        voicePartialTranscript: controller.voicePartialTranscript
      )

      // Bottom toolbar
      FloatingChatToolbarView(
        fastMode: $fastMode,
        inputText: $inputText,
        selectedMode: $selectedMode,
        outputMode: $outputMode,
        selectedMediaModelID: $selectedMediaModelID,
        mediaConfig: $mediaConfig,
        canSend: canSendMessage,
        wsManager: wsManager,
        controller: controller,
        onAttach: { isInlineAttachmentMenuRequested = true },
        onHistory: { onToggleHistory?() },
        onNewChat: startNewChat,
        onStartIndexing: startIndexingMode,
        onVoiceInput: { controller.onVoiceInputToggled?() },
        onSend: sendMessage
      )

    }
    .background {
      Group {
        if theme.usesGlassEffect {
          ZStack {
            // 1. The Blur Layer
            RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
              .fill(.ultraThinMaterial)
            // 2. The Universal Tint Layer
            if let overlay = theme.glassOverlay {
              RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
                .fill(overlay)
            }
          }
        } else {
          // Solid mode - no glass effect
          RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
            .fill(theme.solidBackground)
        }
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
        .stroke(theme.textColor.opacity(0.11), lineWidth: 0.7)
    }
  }

  // Custom blur transition for compatibility
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

  private struct WindowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
      value = max(value, nextValue())
    }
  }

}
