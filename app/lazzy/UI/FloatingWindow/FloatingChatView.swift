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
  @StateObject var conversationStore = ComposerConversationStore()
  @StateObject var workingDirectoryStore = WorkingDirectoryStore()
  @State var isInlineAttachmentMenuRequested = false
  @State var isInlineAttachmentMenuActive = false
  @State var isInlineCommandMenuActive = false
  @State var debugMenuStep: DebugComposerMenuStep?

  @State var inputText = ""
  @State var editorDocumentID = UUID()
  @State var revisionSession = ComposerRevisionSession()
  @State var revisionTarget: ConversationBranchFrom?
  @State var branchSubmission: ComposerBranchSubmission?
  @State var branchRecoveryDraft: ComposerDraft?
  @State var branchSnapshots: [String: ComposerBranchSnapshot] = [:]
  @State var loadingBranchID: String?
  @State var messages: [ChatMessage] = []  // All chat exchanges
  @State var streamingResponse = ""  // Current streaming AI response
  @State var lastCompletedResponse = ""  // Keeps the last response visible after streaming ends
  @State var responseEvents: [AgentResponseEvent] = []
  @State var isThinking = false  // Shows loading state before first chunk arrives
  @State var activeMessageIndex: Int? = nil  // Index of the message currently being viewed
  @State var selectedMode = "Auto"
  @State var isMediaDropTargeted = false
  @State var fastMode = false  // Fast mode toggle
  @FocusState var isInputFocused: Bool
  @State var shortcutMonitor: Any?
  @State var debugDemoTypingTask: Task<Void, Never>?
  @State var remoteConnectionTask: Task<Void, Never>?

  // Stats tracking
  @State var timeToFirstChunk: Int? = nil  // ms
  @State var lastTokenCount: Int? = nil
  @State var lastDurationMs: Int? = nil
  @State var requestStartTime: Date? = nil  // For live timer
  @State var currentActivity: String = "Thinking..."  // Dynamic AI activity status
  @State var errorMessage: String? = nil  // Error message state

  // Theme manager reference
  @ObservedObject var theme = ThemeManager.shared
  @ObservedObject var questions = AgentQuestionCenter.shared

  init(controller: FloatingWindowController, wsManager: WebSocketManager,
       onClose: @escaping () -> Void, onToggleHistory: (() -> Void)? = nil,
       onHistoryRefresh: (() -> Void)? = nil, onNewChat: (() -> Void)? = nil) {
    self.controller = controller
    self.wsManager = wsManager
    self.onClose = onClose
    self.onToggleHistory = onToggleHistory
    self.onHistoryRefresh = onHistoryRefresh
    self.onNewChat = onNewChat
    _conversationStore = StateObject(wrappedValue: ComposerConversationStore(endpoint: wsManager.runtimeEndpoint))
    _workingDirectoryStore = StateObject(wrappedValue: WorkingDirectoryStore())
  }

  private var pendingQuestion: AgentQuestionEnvelope? {
    questions.question(for: ObjectIdentifier(wsManager))
  }

  var body: some View {
    trackRemoteConnection(ZStack(alignment: .topTrailing) {
      Group {
        if controller.isExpanded || controller.isManuallyResized {
          FloatingChatExpandedLayout {
            expandedSection
          } composer: {
            VStack(spacing: 12) {
              if !controller.isExpanded { conversationHeader }
              composerSection
            }
          }
        } else {
          VStack(spacing: 12) {
            conversationHeader
            if revisionSession.messageNumber == nil && (!streamingResponse.isEmpty || !lastCompletedResponse.isEmpty
              || !visibleResponseEvents.isEmpty || !selectedResponseParts.isEmpty || isThinking || errorMessage != nil || !messages.isEmpty)
            {
              responseSection
            }
            composerSection
          }
          .fixedSize(horizontal: false, vertical: true)
        }
      }
      .onAppear {
        setupWSManager()
        loadCurrentConversation()
        refreshComposerResources()
        if let text = controller.initialDraftText, inputText.isEmpty {
          inputText = text
          controller.initialDraftText = nil
        }
        wsManager.requestConversationBranches()
        // Add initial content if present
        if let content = controller.detectedContent {
          addContextIfNeeded(content)
        }
        isInputFocused = pendingQuestion == nil
        questions.setComposerVisible(controller.isVisible, for: ObjectIdentifier(wsManager))
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
        rememberBranch(draft: revisionSession.originalDraft)
        questions.setComposerVisible(false, for: ObjectIdentifier(wsManager))
        removeShortcutMonitor()
#if DEBUG
        controller.onDebugDemoKeyDown = nil
        debugDemoTypingTask?.cancel()
        debugMenuStep = nil
#endif
      }
      .onChange(of: controller.initialDraftText) { _, text in
        if let text, inputText.isEmpty { inputText = text; controller.initialDraftText = nil }
      }
      .onChange(of: controller.detectedContent) { _, newValue in
        if let content = newValue {
          addContextIfNeeded(content)
        }
      }
      .onChange(of: controller.isVisible) { _, visible in
        questions.setComposerVisible(visible, for: ObjectIdentifier(wsManager))
      }
      .onChange(of: pendingQuestion?.id) { _, id in
        isInputFocused = id == nil && controller.isVisible
      }
      .onChange(of: wsManager.isStreaming) { _, isStreaming in
        // Reset thinking state when streaming stops (e.g., user pressed stop)
        if !isStreaming {
          isThinking = false
        }
      }
      .onChange(of: wsManager.conversationBranchState) { _, state in applyBranchReferences(state) }
    })
    .padding(.top, 8)
    .padding(.bottom, controller.isExpanded ? 8 : 0)
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
          .themedSurface(in: Capsule())
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
    // Keep SwiftUI content aligned to the panel's current user-selected width.
    // Media players and images must fill this proposal instead of shrinking
    // the entire composer around their
    // intrinsic size.
    // Give the entire expanded hierarchy a finite native height. In particular,
    // a history reload must not turn the transcript's ideal height into the
    // proposal used to position the composer.
    .frame(
      width: controller.windowContentWidth,
      height: controller.contentViewportHeight,
      alignment: .topLeading
    )
  }

  private func trackRemoteConnection<Content: View>(_ content: Content) -> some View {
    content
      .onChange(of: wsManager.isConnected) { _, connected in
        if connected {
          wsManager.requestConversationBranches()
          if let selected = workingDirectoryStore.remoteWorkspace,
            selected.machineID == wsManager.remoteEndpoint?.machineID
          {
            workingDirectoryStore.setRemoteConnectionStatus(.connected)
          }
        }
      }
      .onChange(of: wsManager.remoteEndpoint) { _, _ in
        conversationStore.updateEndpoint(wsManager.runtimeEndpoint)
      }
      .onChange(of: wsManager.lastError) { _, error in
        guard let error, let selected = workingDirectoryStore.remoteWorkspace,
          wsManager.remoteEndpoint?.machineID == selected.machineID, !wsManager.isConnected
        else { return }
        workingDirectoryStore.setRemoteConnectionStatus(.failed(error))
      }
      .onChange(of: workingDirectoryStore.remoteWorkspace) { _, target in
        connectRemoteWorkspace(target)
      }
      .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
        guard let target = workingDirectoryStore.remoteWorkspace else { return }
        connectRemoteWorkspace(target, forceReconnect: true)
      }
  }

  @ViewBuilder
  private var conversationHeader: some View {
    if hasConversationNavigation && !controller.isExpanded {
      FloatingChatHeaderView(
        messages: messages,
        activeMessageIndex: $activeMessageIndex,
        lastCompletedResponse: $lastCompletedResponse,
        canRevise: canReviseMessages,
        onRevise: reviseMessage
      )
      .padding(.horizontal, 16)
      .zIndex(2)
    }
  }

  private var composerSection: some View {
    VStack(spacing: 0) {
      ProviderConversationNotice(conversation: wsManager.currentConversation, onNewChat: startNewChat)
      inputAndToolbarSection
      WorkingDirectoryTray(store: workingDirectoryStore, onReconnect: {
        connectRemoteWorkspace(workingDirectoryStore.remoteWorkspace, forceReconnect: true)
      }) { presented in
        isInputFocused = !presented && pendingQuestion == nil
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .layoutPriority(1)
  }

  @ViewBuilder
  private var expandedSection: some View {
    FloatingChatExpandedView(
      messages: revisionSession.isBranchingAfterResponse ? Array(messages.prefix(revisionSession.messageNumber ?? messages.count)) : messages,
      isThinking: isThinking,
      streamingResponse: streamingResponse,
      currentActivity: currentActivity,
      responseEvents: visibleResponseEvents,
      canRevise: canReviseMessages,
      onRevise: reviseMessage,
      onBranch: branchAfterResponse,
      gitWorkspace: workingDirectoryStore.path,
      gitConversationID: wsManager.currentConversationId,
      gitEndpoint: wsManager.runtimeEndpoint
    )
    .themedSurface(in: RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous))
  }

  @ViewBuilder
  private var responseSection: some View {
    FloatingChatResponseView(
      streamingResponse: streamingResponse,
      lastCompletedResponse: lastCompletedResponse,
      completedParts: selectedResponseParts,
      responseEvents: visibleResponseEvents,
      isThinking: isThinking,
      errorMessage: errorMessage,
      currentActivity: currentActivity,
      maxStreamingHeight: maxStreamingHeight,
      canBranchResponse: canReviseMessages && selectedGitMessage?.branchReference?.canBranchAfter == true,
      onBranchResponse: { branchAfterResponse(activeMessageIndex ?? messages.count - 1) },
      gitMessage: selectedGitMessage,
      gitWorkspace: workingDirectoryStore.path,
      gitConversationID: wsManager.currentConversationId,
      gitEndpoint: wsManager.runtimeEndpoint
    )
    .themedSurface(in: RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
        .stroke(theme.textColor.opacity(theme.mode == .liquidGlass ? 0 : 0.10), lineWidth: 0.7)
        .allowsHitTesting(false)
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
      if let request = pendingQuestion {
        ComposerQuestionView(request: request, center: questions, controller: controller, onClose: onClose)
      } else {
        if let number = revisionSession.messageNumber {
          ComposerRevisionBanner(messageNumber: number, afterResponse: revisionSession.isBranchingAfterResponse, error: errorMessage, onCancel: cancelMessageRevision)
            .padding(.horizontal, 18).padding(.top, 12)
        }
        // Main input area
        FloatingChatInputView(
          inputText: $inputText,
          debugMenuStep: $debugMenuStep,
          isInputFocused: $isInputFocused,
          controller: controller,
          onClose: onClose,
          onSubmit: sendMessage,
          onPasteAttachment: handlePaste,
          fileAttachments: pendingAttachments,
          textContexts: sessionContexts,
          onRemoveTextContext: { context in sessionContexts.removeAll { $0 == context } },
          onAttachTextContext: addContextIfNeeded,
          editorDocumentID: editorDocumentID,
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
          commands: wsManager.customSlashCommands,
          isAttachmentMenuRequested: $isInlineAttachmentMenuRequested,
          isAttachmentMenuActive: $isInlineAttachmentMenuActive,
          isCommandMenuActive: $isInlineCommandMenuActive,
          skillsDirectory: skillsDirectory,
          workingDirectoryStore: workingDirectoryStore,
          browserTabStore: browserTabStore,
          conversationStore: conversationStore,
          currentConversationID: wsManager.currentConversationId,
          onAttachFile: addFileAttachment,
          onAttachAttachment: addPendingAttachment,
          onRemoveFileAttachment: removeAttachment,
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
          canSend: canSendMessage,
          wsManager: wsManager,
          controller: controller,
          onAttach: { isInlineAttachmentMenuRequested = true },
          onHistory: { onToggleHistory?() },
          onNewChat: startNewChat,
          onStartIndexing: startIndexingMode,
          onVoiceInput: { controller.onVoiceInputToggled?() },
          onSend: sendMessage,
          isRevising: revisionSession.messageNumber != nil,
          isBranchingAfterResponse: revisionSession.isBranchingAfterResponse,
          gitWorkspace: workingDirectoryStore.path,
          gitConversationID: wsManager.currentConversationId,
          gitEndpoint: wsManager.runtimeEndpoint,
          branches: availableBranches,
          onSelectBranch: switchConversationBranch
        )
      }
    }
    .themedSurface(in: RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: theme.borderRadius, style: .continuous)
        .stroke(theme.textColor.opacity(theme.mode == .liquidGlass ? 0 : 0.11), lineWidth: 0.7)
        .allowsHitTesting(false)
    }
  }

  // Custom blur transition for compatibility
  private var selectedGitMessage: ChatMessage? {
    let index = activeMessageIndex ?? messages.count - 1
    return messages.indices.contains(index) ? messages[index] : nil
  }

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
