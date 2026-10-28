import AppKit
import SwiftUI

extension FloatingChatView {
  var maxStreamingHeight: CGFloat {
    // 60% of screen height
    if let screen = NSScreen.main {
      return screen.visibleFrame.height * 0.6
    }
    return 400  // Fallback
  }

  // MARK: - Actions

  func setupWSManager() {
    installConversationLoadHandler()
    wsManager.onProviderSession = acceptBranchSession
    wsManager.connect()

    // Handle streaming chunks in real-time
    wsManager.onChunk = { chunk in
      // Identify first chunk to stop thinking state
      if isThinking {
        isThinking = false
      }
      appendResponseText(chunk)
      streamingResponse += chunk
    }

    // Handle first chunk timing
    wsManager.onFirstChunk = { ttfc in
      timeToFirstChunk = ttfc
      print("⚡ Time to first chunk: \(ttfc)ms")
    }

    // Handle completion - save response and keep it visible
    wsManager.onComplete = { [self] conversationId, assistantId, userId, tokenCount, durationMs in
      let response = streamingResponse
      deactivateResponseActivities()
      if !messages.isEmpty {
        messages[messages.count - 1].responseParts = responseEvents.map(\.messagePart)
        messages[messages.count - 1].assistantMessageId = assistantId
        messages[messages.count - 1].userMessageId = userId
        if response.isEmpty { messages[messages.count - 1].aiResponse = "" }
      }
      if !response.isEmpty {
        // Update the last message with the AI response and backend IDs
        if !messages.isEmpty {
          messages[messages.count - 1].aiResponse = response
          messages[messages.count - 1].assistantMessageId = assistantId
          messages[messages.count - 1].userMessageId = userId
        }
        // Keep the response visible
        lastCompletedResponse = response
      }

      // If no active index was set, highlight the latest one
      if activeMessageIndex == nil {
        activeMessageIndex = messages.count - 1
      }

      // Store stats
      lastTokenCount = tokenCount
      lastDurationMs = durationMs

      streamingResponse = ""
      branchRecoveryDraft = nil
      isThinking = false
      deactivateResponseActivities()
      print(
        "✅ Conversation ID: \(conversationId), Assistant ID: \(assistantId ?? "nil"), User ID: \(userId ?? "nil"), Tokens: \(tokenCount ?? 0), Duration: \(durationMs ?? 0)ms"
      )

      // Refresh history panel so new conversation appears
      retainSentAttachments(conversationID: conversationId)
      onHistoryRefresh?()
    }

    wsManager.onChatSent = { request in
      // Keep subsequent turns on the routed provider without changing global manual preferences.
      if let agent = request.agent { self.controller.selectedAgent = agent }
      self.controller.selectedModel = request.model
      self.controller.selectedModelSettings = request.modelSettings
      if self.wsManager.isResumingDetachedRun {
        self.messages.append(ChatMessage(userPrompt: request.displayText ?? "Continue task", context: [], aiResponse: nil))
        self.activeMessageIndex = self.messages.count - 1
      }
      self.prepareForRequest()
    }

    // Handle activity status updates
    wsManager.onAgentActivityUpdate = { update in
      currentActivity = update.status
      appendActivity(update)
    }

    // Handle generalized errors
    wsManager.onError = { [self] error in
      print("❌ FloatingChatView received error callback: \(error)")
      // WebSocketManager marks streaming inactive before invoking this callback,
      // so gating on streaming state can silently discard late provider errors.
      isThinking = false
      deactivateResponseActivities()
      errorMessage = error
      handleBranchError()
      retainSentAttachments()
      print("❌ UI received error: \(error)")
    }
  }

  /// Reset UI state for a new request
  func prepareForRequest() {
    streamingResponse = ""
    lastCompletedResponse = ""
    responseEvents = []
    isThinking = true
    currentActivity = "Working..."
    errorMessage = nil  // Reset error state
    timeToFirstChunk = nil
    lastTokenCount = nil
    lastDurationMs = nil
  }

  var visibleResponseEvents: [AgentResponseEvent] {
    isThinking || !streamingResponse.isEmpty ? responseEvents : []
  }

  var selectedResponseParts: [MessagePart] {
    let index = activeMessageIndex ?? (messages.count - 1)
    guard messages.indices.contains(index) else { return [] }
    return messages[index].responseParts
  }

  func appendActivity(_ update: AgentActivityUpdate) {
    if let kind = update.event?.kind, ["lifecycle", "status"].contains(kind) { return }
    let trimmed = update.status.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    let incomingID = update.event?.id
    if let incomingID,
      let existingIndex = responseEvents.lastIndex(where: {
        $0.kind == .activity && $0.activity?.id == incomingID
      })
    {
      responseEvents[existingIndex].text = trimmed
      responseEvents[existingIndex].activity = update.event
      responseEvents[existingIndex].toolName = update.toolName
      responseEvents[existingIndex].isActive = update.event?.phase != "completed"
        && update.event?.phase != "failed"
      if responseEvents[existingIndex].isActive {
        for index in responseEvents.indices
        where index != existingIndex && responseEvents[index].kind == .activity {
          responseEvents[index].isActive = false
        }
      }
      return
    }

    deactivateResponseActivities()

    if incomingID == nil, let lastIndex = responseEvents.indices.last,
      responseEvents[lastIndex].kind == .activity,
      responseEvents[lastIndex].text == trimmed
    {
      responseEvents[lastIndex].isActive = true
      responseEvents[lastIndex].activity = update.event
      responseEvents[lastIndex].toolName = update.toolName
      return
    }

    responseEvents.append(AgentResponseEvent(
      kind: .activity,
      text: trimmed,
      isActive: update.event?.phase != "completed" && update.event?.phase != "failed",
      activity: update.event,
      toolName: update.toolName
    ))
    trimResponseEventsIfNeeded()
  }

  func appendResponseText(_ text: String) {
    guard !text.isEmpty else { return }

    deactivateResponseActivities()

    if let lastIndex = responseEvents.indices.last,
      responseEvents[lastIndex].kind == .text
    {
      responseEvents[lastIndex].text += text
    } else {
      responseEvents.append(AgentResponseEvent(kind: .text, text: text))
    }
    trimResponseEventsIfNeeded()
  }

  func trimResponseEventsIfNeeded() {
    let maximumEvents = 10_000
    if responseEvents.count > maximumEvents {
      responseEvents.removeFirst(responseEvents.count - maximumEvents)
    }
  }

  func deactivateResponseActivities() {
    for index in responseEvents.indices where responseEvents[index].kind == .activity {
      responseEvents[index].isActive = false
    }
  }

  func sendMessage() {
    guard canSendMessage, validateDraftAttachments() else { return }

    let draft = composerDraft
    let userText = draft.resolvedText
    let branchFrom = revisionSession.messageNumber == nil ? nil : beginBranchSubmission(draft)
    if revisionSession.messageNumber != nil && branchFrom == nil { return }

    // Browsing an earlier exchange never truncates provider-owned history.

    // Reset active index so the new message will become the highlighted one on complete
    activeMessageIndex = nil

    prepareForRequest()

    // Prepare context for this message (snapshot of current accumulated context)
    let currentContexts = sessionContexts

    // Build prompt with context markers for server parsing
    var contextPart = ""
    if !currentContexts.isEmpty {
      let contextTexts = currentContexts.compactMap { $0.text }.joined(separator: "\n\n---\n\n")
      if !contextTexts.isEmpty {
        contextPart = "\"User Context:\"\n\(contextTexts)\n\n"
      }
    }
    if !pendingMCPAttachments.isEmpty {
      let mcpContext = pendingMCPAttachments
        .map { "- \($0.name): \($0.detail)" }
        .joined(separator: "\n")
      contextPart += "\"Selected MCP Capabilities:\"\n\(mcpContext)\n\n"
    }
    if !pendingCommandAliases.isEmpty {
      let commandContext = pendingCommandAliases
        .map { "- /\($0.command): \($0.replacementText)" }
        .joined(separator: "\n")
      contextPart += "\"Selected Composer Commands:\"\n\(commandContext)\n\n"
    }
    let displayText = displayTextForMessage(userText)

    // Add user message to messages array (Store context separately!)
    if branchFrom == nil { messages.append(
      ChatMessage(
        userPrompt: displayText,  // Store raw user text plus selected command labels
        context: currentContexts,  // Store context snapshot
        aiResponse: nil,
        attachments: draft.attachments,
        draft: draft
      )) }

    let skills = pendingSkills
    let browserTabs = pendingBrowserTabs.isEmpty ? nil : pendingBrowserTabs
    let selectedMCPServerIds = uniqueServerIds(from: pendingMCPAttachments)
    let mcpServerIds = selectedMCPServerIds.isEmpty ? nil : selectedMCPServerIds

    // Send to server - WebSocketManager handles conversation ID automatically
    wsManager.sendChat(
      text: userText,
      displayText: displayText,
      files: draft.files,
      workspacePath: workingDirectoryStore.url?.path,
      branchFrom: branchFrom,
      attachmentContext: contextPart.isEmpty ? nil : contextPart,
      fastMode: fastMode,
      zeroDataRetention: AISettings.zeroDataRetention,
      mcpServerIds: mcpServerIds,
      skills: skills,
      browserTabs: browserTabs,
      agent: controller.selectedAgent,
      model: controller.selectedModel,
      modelSettings: controller.selectedModelSettings
    )
    if branchFrom == nil { clearSentDraft() }
    retainSentAttachments()
  }

  func displayTextForMessage(_ userText: String) -> String {
    userText
  }

  func uniqueServerIds(from attachments: [ComposerMCPAttachment]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for attachment in attachments where !seen.contains(attachment.serverId) {
      seen.insert(attachment.serverId)
      result.append(attachment.serverId)
    }
    return result
  }

  func uniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for value in values where seen.insert(value).inserted {
      result.append(value)
    }
    return result
  }

  func uniqueSkills(_ skills: [SkillAttachment]) -> [SkillAttachment] {
    var seen = Set<String>()
    var result: [SkillAttachment] = []
    for skill in skills where seen.insert(skill.id).inserted {
      result.append(skill)
    }
    return result
  }

  /// Start a new chat session - clears local state and notifies parent
  func startNewChat() {
    conversationStore.cancelAttachment()
    conversationStore.cancelSearch()
    // Clear local state
    messages = []
    activeMessageIndex = nil
    revisionSession = ComposerRevisionSession()
    revisionTarget = nil
    branchSubmission = nil
    branchRecoveryDraft = nil
    editorDocumentID = UUID()
    sessionContexts = []

    streamingResponse = ""
    lastCompletedResponse = ""
    responseEvents = []
    isThinking = false
    inputText = ""
    pendingAttachments = []
    pendingSkills = []
    pendingBrowserTabs = []
    pendingMCPAttachments = []
    pendingCommandAliases = []
    if let current = controller.detectedContent { addContextIfNeeded(current) }

    // Reset the window anchor to the current position so it doesn't jump
    controller.resetAnchor()

    // Tell parent to handle new chat (will clear wsManager conversation)
    onNewChat?()
  }

  /// Start the interactive UI indexing mode
  func startIndexingMode() {
    print("🎯 Starting UI Indexing Mode")

    // Clear current state for fresh indexing session
    prepareForRequest()

    // Send special message to start indexing agent
    wsManager.sendChat(
      text: "[INDEXING_MODE] User wants to index an app's UI. Start the interactive indexing flow.",
      files: [],
      workspacePath: workingDirectoryStore.url?.path,
      fastMode: false,
      zeroDataRetention: AISettings.zeroDataRetention
    )
  }

  /// Load current conversation from server if one exists
  func loadCurrentConversation() {
    // Only load if we have a current conversation and no local messages yet
    guard let conversationId = wsManager.currentConversationId,
      messages.isEmpty,
      sessionContexts.isEmpty
    else {
      return
    }

    print("📂 Loading current conversation: \(conversationId)")
    wsManager.loadConversation(id: conversationId)
  }

  /// This must be installed before a reconnect can receive a conversation
  /// response. The task switcher may set its conversation ID either just
  /// before or just after this view appears.
  func installConversationLoadHandler() {
    wsManager.onConversationLoaded = { [self] conv, loadedMessages in
      DispatchQueue.main.async {
        guard self.wsManager.currentConversationId == conv.id else { return }
        self.errorMessage = nil
        if let provider = conv.provider, AgentProvider(rawValue: provider) != nil {
          DetachSettings.selectedAgent = provider
          DetachSettings.setSelectedModel(conv.model, for: provider)
        }
        if let path = conv.workspacePath {
          if conv.isProviderHistory { self.workingDirectoryStore.clear() }
          self.workingDirectoryStore.setDirectory(URL(fileURLWithPath: path))
        } else if conv.isProviderHistory {
          self.workingDirectoryStore.clear()
        }
        // Convert server messages to local ChatMessage format
        var pairs: [ChatMessage] = []
        var i = 0
        while i < loadedMessages.count {
          let msg = loadedMessages[i]
          if msg.isUser {
            var chatMsg = ChatMessage(
              userMessageId: msg.id,
              assistantMessageId: nil,
              userPrompt: msg.content,
              context: nil,  // History doesn't have context data separated yet
              aiResponse: nil
            )
            if i + 1 < loadedMessages.count && loadedMessages[i + 1].isAssistant {
              let assistant = loadedMessages[i + 1]
              chatMsg.aiResponse = assistant.content
              chatMsg.responseParts = ChatTranscript.parts(text: assistant.content, structured: assistant.parts)
              chatMsg.assistantMessageId = assistant.id
              i += 1
            }
            pairs.append(chatMsg)
          }
          i += 1
        }

        self.responseEvents = []
        self.streamingResponse = ""
        self.isThinking = false
        self.cancelMessageRevision()
        let restored = AISettings.zeroDataRetention ? pairs
          : SentMessageAttachmentStore.restore(pairs, conversationID: conv.id)
        self.messages = restored.map { $0.restoringAvailableAttachments() }
        self.activeMessageIndex = pairs.count - 1
        let isSwitching = self.loadingBranchID == conv.id
        let stored = ComposerBranchDraftStore.load(conv.id)
        if isSwitching || self.inputText.isEmpty {
          if let draft = self.branchSnapshots[conv.id]?.draft ?? stored?.draft { self.applyDraft(draft) }
        }
        let selected = self.branchSnapshots[conv.id]?.selectedMessage ?? stored?.selectedMessage
        if let selected, self.messages.indices.contains(selected) { self.activeMessageIndex = selected }
        self.loadingBranchID = nil
        self.wsManager.requestConversationBranches()
        self.applyBranchReferences(self.wsManager.conversationBranchState)

        if let lastAssistant = loadedMessages.last(where: { $0.isAssistant }) {
          self.lastCompletedResponse = self.activeMessageIndex.flatMap {
            self.messages.indices.contains($0) ? self.messages[$0].aiResponse : nil
          } ?? lastAssistant.content
        }
      }
    }
  }
}
