import Auth
import Foundation
import Combine

extension WebSocketManager {
  func sendChat(
    text: String, displayText: String? = nil, files: [FileAttachmentRequest] = [],
    conversationId: String? = nil, workspacePath: String? = nil, branchFrom: ConversationBranchFrom? = nil,
    integrations: [String]? = nil, systemPrompt: String? = nil, attachmentContext: String? = nil,
    fastMode: Bool = false,
    userId: String? = nil, zeroDataRetention: Bool? = nil,
    actionId: String? = nil, mcpServerIds: [String]? = nil, skills: [SkillAttachment]? = nil,
    browserTabs: [BrowserTabAttachment]? = nil,
    agent: String? = nil, model: String? = nil, modelSettings: AgentModelSettings? = nil
  ) {
    guard isConnected, !isStoppingRun else {
      lastError = "Not connected to server"
      onError?("Not connected to server")
      return
    }

    // Use provided conversationId or current one for follow-ups
    let convId = conversationId ?? currentConversationId
    let pinnedChoice = convId != nil && convId == currentConversationId ? autoRoutedChoice : nil
    let resolvedAgent = pinnedChoice?.agent ?? agent ?? DetachSettings.selectedAgent
    let resolvedModel = pinnedChoice != nil ? pinnedChoice?.model : model ?? DetachSettings.selectedModel(for: resolvedAgent)
    let resolvedModelSettings = pinnedChoice != nil ? pinnedChoice?.effort.map { AgentModelSettings(reasoningEffort: $0) } : modelSettings
      ?? DetachSettings.modelSettings(for: resolvedAgent, model: resolvedModel)

    let request = ChatRequest(
      text: text, displayText: displayText, files: files.isEmpty ? nil : files,
      runId: UUID().uuidString,
      conversationId: convId,
      branchFrom: branchFrom,
      workspacePath: workspacePath,
      integrations: integrations, systemPrompt: systemPrompt, attachmentContext: attachmentContext,
      fastMode: fastMode,
      userId: userId,
      model: resolvedModel,
      agent: resolvedAgent,
      modelSettings: resolvedModelSettings,
      zeroDataRetention: zeroDataRetention,
      actionId: actionId,
      mcpServerIds: mcpServerIds,
      skills: skills,
      browserTabs: browserTabs)

    submitChatRequest(request)
  }


  func submitChatRequest(_ request: ChatRequest) {
    guard isConnected, !isStreaming, !isStoppingRun else { return }
    if beginAutoRouting(request) { return }
    dispatchChatRequest(request)
  }

  func dispatchChatRequest(_ request: ChatRequest) {
    guard isConnected, !isStreaming, !isStoppingRun else { return }
    var request = request
    if request.permissionMode == nil {
      request.permissionMode = DetachSettings.permissionMode(for: request.agent ?? DetachSettings.selectedAgent).rawValue
    }
    if let instructions = AISettings.additionalInstructions,
      request.systemPrompt?.contains(instructions) != true {
      request.systemPrompt = [instructions, request.systemPrompt].compactMap { $0 }.joined(separator: "\n\n")
    }
    currentResponse = ""
    lastContextSummary = nil
    isStreaming = true
    lastError = nil
    activeChatRequest = request
    sendRequest(request, label: "chat")
    onChatSent?(request)
    chatSentListeners.forEach { $0(request) }
  }


  func listConversations(limit: Int = 500, offset: Int = 0) {
    guard isConnected else { return }
    let request = ListConversationsRequest(limit: limit, offset: offset)
    sendRequest(request, label: "list_conversations")
  }

  func loadMoreConversations() {
    guard hasMoreConversations, !isLoadingMoreConversations, isConnected else { return }
    isLoadingMoreConversations = true
    listConversations(offset: nextConversationOffset)
  }


  func deleteConversation(id: String) {
    guard isConnected else { return }
    let request = DeleteConversationRequest(conversationId: id)
    sendRequest(request, label: "delete_conversation")
  }


  func searchMessages(query: String, limit: Int = 20) {
    guard isConnected else { return }
    let request = SearchMessagesRequest(query: query, limit: limit)
    sendRequest(request, label: "search")
  }


  func editMessage(id: String, content: String) {
    guard isConnected else { return }
    let request = EditMessageRequest(messageId: id, content: content)
    sendRequest(request, label: "edit_message")
  }


  func deleteMessage(id: String) {
    guard isConnected else { return }
    let request = DeleteMessageRequest(messageId: id)
    sendRequest(request, label: "delete_message")
  }


  func startNewConversation() {
    cancelAutoRouting()
    autoRoutedChoice = nil
    cancelConversationLoad()
    currentConversationId = nil
    currentConversation = nil
    currentConversationTitle = nil
    currentResponse = ""
  }


  func loadConversation(id: String) {
    cancelAutoRouting()
    if id != currentConversationId { autoRoutedChoice = nil }
    if isStreaming && currentConversationId == id { return }
    currentConversationId = id
    currentConversation = conversations.first(where: { $0.id == id })
    currentConversationTitle = currentConversation?.isProviderHistory == true ? currentConversation?.title
      : conversationTitleCache.title(for: id) ?? currentConversation?.title
    if isConnected {
      getConversation(id: id)
    }
  }


  func listMCPServers() {
    guard isConnected else { return }
    isLoadingMCPServers = true
    let request = ListMCPServersRequest()
    sendRequest(request, label: "list_mcp_servers")
  }


  func addMCPServer(
    name: String, transport: String, command: String?, args: [String]?, url: String?
  ) {
    guard isConnected else { return }
    let request = AddMCPServerRequest(
      name: name,
      transport: transport,
      command: command,
      args: args,
      url: url,
      headers: nil,
      env: nil,
      enabled: true
    )
    sendRequest(request, label: "add_mcp_server")
  }


  func deleteMCPServer(id: String) {
    guard isConnected else { return }
    let request = DeleteMCPServerRequest(serverId: id)
    sendRequest(request, label: "delete_mcp_server")
  }


  func connectMCPServer(id: String) {
    guard isConnected else { return }
    let request = ConnectMCPServerRequest(serverId: id)
    sendRequest(request, label: "connect_mcp_server")
  }


  func disconnectMCPServer(id: String) {
    guard isConnected else { return }
    let request = DisconnectMCPServerRequest(serverId: id)
    sendRequest(request, label: "disconnect_mcp_server")
  }


  func listComposioIntegrations(limit: Int = 10, offset: Int = 0, query: String? = nil) {
    guard isConnected else { return }
    isLoadingComposio = true
    composioError = nil
    let userId = AuthManager.shared.currentUser?.id.uuidString
    let request = ListComposioIntegrationsRequest(
      limit: limit, offset: offset, query: query, userId: userId)
    sendRequest(request, label: "list_composio_integrations")
  }


  func connectComposioAccount(toolkit: String, callbackUrl: String? = nil) {
    guard isConnected else { return }
    connectingToolkit = toolkit
    let userId = AuthManager.shared.currentUser?.id.uuidString
    let request = ConnectComposioAccountRequest(
      toolkit: toolkit, userId: userId, callbackUrl: callbackUrl)
    sendRequest(request, label: "connect_composio_account")
  }


  func listComposioConnections() {
    guard isConnected else { return }
    let userId = AuthManager.shared.currentUser?.id.uuidString
    let request = ListComposioConnectionsRequest(userId: userId)
    sendRequest(request, label: "list_composio_connections")
  }


  func disconnectComposioAccount(connectionId: String) {
    guard isConnected else { return }
    let userId = AuthManager.shared.currentUser?.id.uuidString
    let request = DisconnectComposioAccountRequest(connectionId: connectionId, userId: userId)
    sendRequest(request, label: "disconnect_composio_account")
  }


  func updateAISettings(
    agent: String? = nil, model: String?, temperature: Double?, maxSteps: Int?,
    systemPrompt: String?, zeroDataRetention: Bool? = nil
  ) {
    guard isConnected else { return }
    let request = UpdateAISettingsRequest(
      agent: agent,
      model: model,
      temperature: temperature,
      maxSteps: maxSteps,
      systemPrompt: systemPrompt,
      zeroDataRetention: zeroDataRetention
    )
    sendRequest(request, label: "update_ai_settings")
  }


  func listWorkflows() {
    guard isConnected else { return }
    sendRequest(ListWorkflowsRequest(), label: "list_workflows")
  }


  func addWorkflow(
    name: String, prompt: String, systemImage: String?, shortcut: String?,
    mcpServerIds: [String]? = nil, skills: [SkillAttachment]? = nil,
    inputPolicy: String? = "none", executionMode: String? = "run_immediately"
  ) {
    guard isConnected else { return }
    let request = AddWorkflowRequest(
      name: name,
      prompt: prompt,
      systemImage: systemImage,
      shortcut: shortcut,
      mcpServerIds: mcpServerIds,
      skills: skills,
      inputPolicy: inputPolicy,
      executionMode: executionMode
    )
    sendRequest(request, label: "add_workflow")
  }


  func updateWorkflow(
    actionId: String, name: String?, prompt: String?, systemImage: String?, shortcut: String?,
    enabled: Bool?, position: Int?, mcpServerIds: [String]? = nil,
    skills: [SkillAttachment]? = nil, inputPolicy: String? = nil, executionMode: String? = nil
  ) {
    guard isConnected else { return }
    let request = UpdateWorkflowRequest(
      actionId: actionId,
      name: name,
      prompt: prompt,
      systemImage: systemImage,
      shortcut: shortcut,
      enabled: enabled,
      position: position,
      mcpServerIds: mcpServerIds,
      skills: skills,
      inputPolicy: inputPolicy,
      executionMode: executionMode
    )
    sendRequest(request, label: "update_workflow")
  }


  func deleteWorkflow(actionId: String) {
    guard isConnected else { return }
    sendRequest(DeleteWorkflowRequest(actionId: actionId), label: "delete_workflow")
  }


  func listSlashCommands() {
    guard isConnected else { return }
    let request = ListSlashCommandsRequest()
    sendRequest(request, label: "list_slash_commands")
  }


  func addSlashCommand(
    command: String, title: String, subtitle: String? = nil, systemImage: String? = nil,
    replacementText: String? = nil, promptInstruction: String? = nil, mode: ComposerMode? = nil
  ) {
    guard isConnected else { return }
    let request = AddSlashCommandRequest(
      command: command,
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      replacementText: replacementText,
      promptInstruction: promptInstruction,
      mode: mode
    )
    sendRequest(request, label: "add_slash_command")
  }


  func updateSlashCommand(
    commandId: String, command: String? = nil, title: String? = nil, subtitle: String? = nil,
    systemImage: String? = nil, replacementText: String? = nil, promptInstruction: String? = nil,
    mode: ComposerMode? = nil, enabled: Bool? = nil, position: Int? = nil
  ) {
    guard isConnected else { return }
    let request = UpdateSlashCommandRequest(
      commandId: commandId,
      command: command,
      title: title,
      subtitle: subtitle,
      systemImage: systemImage,
      replacementText: replacementText,
      promptInstruction: promptInstruction,
      mode: mode,
      enabled: enabled,
      position: position
    )
    sendRequest(request, label: "update_slash_command")
  }


  func deleteSlashCommand(commandId: String) {
    guard isConnected else { return }
    let request = DeleteSlashCommandRequest(commandId: commandId)
    sendRequest(request, label: "delete_slash_command")
  }


  func sendRequest<T: Encodable>(_ request: T, label: String) {
    guard let data = try? JSONEncoder().encode(request),
      let jsonString = String(data: data, encoding: .utf8)
    else {
      lastError = "Failed to encode \(label) request"
      if label == "chat" { isStreaming = false }
      if label == "list_mcp_servers" { isLoadingMCPServers = false }
      return
    }

    print("📤 Sending \(label) request")

    webSocket?.send(.string(jsonString)) { [weak self] error in
      if let error = error {
        let weakSelf = self
        Task { @MainActor in
          guard let self = weakSelf else { return }
          print("❌ Send error: \(error.localizedDescription)")
          self.lastError = error.localizedDescription
          if label == "chat" { self.isStreaming = false }
          if label == "list_mcp_servers" { self.isLoadingMCPServers = false }
          self.onError?(error.localizedDescription)
        }
      }
    }
  }


  func sendRawRequest(_ request: [String: String], label: String) {
    guard let data = try? JSONSerialization.data(withJSONObject: request),
      let jsonString = String(data: data, encoding: .utf8)
    else {
      lastError = "Failed to encode \(label) request"
      if label == "capabilities" {
        capabilitiesRequestInFlight = false
        isLoadingCapabilities = false
      }
      return
    }

    webSocket?.send(.string(jsonString)) { [weak self] error in
      if let error = error {
        let weakSelf = self
        Task { @MainActor in
          guard let self = weakSelf else { return }
          if label == "capabilities" {
            self.capabilitiesRequestInFlight = false
            self.capabilitiesRefreshQueued = false
            self.capabilitiesTimeoutTask?.cancel()
            self.capabilitiesTimeoutTask = nil
            self.isLoadingCapabilities = false
          }
          self.lastError = error.localizedDescription
          self.onError?(error.localizedDescription)
        }
      }
    }
  }

}
