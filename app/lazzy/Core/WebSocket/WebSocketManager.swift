import Auth
import Combine
import Foundation

#if os(macOS)
  import AppKit
#endif

/// Manages WebSocket connection to the AI server
@MainActor
class WebSocketManager: ObservableObject {

  // MARK: - Published Properties

  @Published private(set) var isConnected = false
  @Published private(set) var currentResponse = ""
  @Published private(set) var isStreaming = false
  @Published private(set) var lastError: String?
  @Published private(set) var currentConversationId: String?
  @Published private(set) var conversations: [Conversation] = []
  @Published private(set) var mcpServers: [MCPServer] = []
  @Published private(set) var isLoadingMCPServers = false
  @Published private(set) var customQuickActions: [QuickAction] = []
  @Published private(set) var workflows: [QuickAction] = []
  @Published private(set) var customSlashCommands: [CustomSlashCommand] = []
  @Published private(set) var agentCapabilities: [AgentCapability] = []
  @Published private(set) var isLoadingCapabilities = false
  @Published private(set) var mediaModels: [MediaModelCapability] = []
  @Published private(set) var defaultAgent: String = DetachSettings.defaultAgent

  // Composio Integration State
  @Published var composioIntegrations: [ComposioIntegration] = []
  @Published var isLoadingComposio = false
  @Published var composioError: String? = nil
  @Published var connectingToolkit: String? = nil
  @Published var hasMoreComposioIntegrations = false
  @Published var totalComposioIntegrations = 0

  // MARK: - Private Properties

  private var webSocket: URLSessionWebSocketTask?
  private var session: URLSession?
  private var pingTimer: Timer?
  private var isConnecting = false
  private let desktopAutomation = DesktopAutomationService()
  private let secretVault = SecretVault.shared
  private var activityListeners: [(String, String?) -> Void] = []
  private var completionListeners: [(String, String?, String?, Int?, Int?) -> Void] = []
  private var errorListeners: [(String) -> Void] = []
  private var creditsListeners: [(String) -> Void] = []
  private var chatSentListeners: [(ChatRequest) -> Void] = []
  private var mediaRunStartedListeners: [(MediaRunStart) -> Void] = []
  private var agentActivityListeners: [(AgentActivityUpdate) -> Void] = []
  private var runCompletionListeners: [(String?, String) -> Void] = []
  private var runErrorListeners: [(String?, String) -> Void] = []
  private var cancellables = Set<AnyCancellable>()
  private var capabilitiesRequestInFlight = false
  private var capabilitiesRefreshQueued = false
  private var capabilitiesTimeoutTask: Task<Void, Never>?

  // MARK: - Callbacks

  var onChunk: ((String) -> Void)?
  var onFirstChunk: ((Int) -> Void)?  // Time to first chunk in ms
  var onComplete: ((String, String?, String?, Int?, Int?) -> Void)?  // (conversationId, assistantId, userId, tokenCount, durationMs)
  var onChatSent: ((ChatRequest) -> Void)?
  var onError: ((String) -> Void)?
  var onCreditsExhausted: ((String) -> Void)?
  var onConversationsLoaded: (([Conversation]) -> Void)?
  var onConversationLoaded: ((Conversation, [Message]) -> Void)?
  var onSearchResults: (([SearchResult]) -> Void)?
  var onImageGenerated: ((String, String) -> Void)?
  var onMediaModels: (([MediaModelCapability]) -> Void)?
  var onMediaJob: ((String?, String, String, String, MediaJob) -> Void)?
  var onMediaQuote: ((String, MediaQuote) -> Void)?
  var onDeleted: ((String) -> Void)?
  var onUpdated: ((String) -> Void)?
  var onMCPServersLoaded: (([MCPServer]) -> Void)?
  // Composio callbacks
  var onComposioIntegrations:
    ((Bool, [ComposioIntegration], Int?, Bool?, Int?, Int?, String?) -> Void)?
  var onComposioAuthUrl: ((String, String, String) -> Void)?  // (url, toolkit, connectionId)
  var onComposioConnections: (([ComposioConnection]) -> Void)?
  var onComposioConnected: ((String, String, String) -> Void)?  // (toolkit, connectionId, status)
  var onComposioDisconnected: ((String) -> Void)?
  // Quick Actions callbacks
  var onQuickActionsList: (([QuickAction]) -> Void)?
  var onQuickActionAdded: ((QuickAction) -> Void)?
  var onQuickActionUpdated: ((QuickAction) -> Void)?
  var onQuickActionDeleted: ((String) -> Void)?
  var onWorkflowsList: (([QuickAction]) -> Void)?
  var onWorkflowAdded: ((QuickAction) -> Void)?
  var onWorkflowUpdated: ((QuickAction) -> Void)?
  var onWorkflowDeleted: ((String) -> Void)?
  // Slash Commands callbacks
  var onSlashCommandsList: (([CustomSlashCommand]) -> Void)?
  var onSlashCommandAdded: ((CustomSlashCommand) -> Void)?
  var onSlashCommandUpdated: ((CustomSlashCommand) -> Void)?
  var onSlashCommandDeleted: ((String) -> Void)?
  // Activity callback
  var onActivityUpdate: ((String, String?) -> Void)?  // (status, toolName)
  var onAgentActivityUpdate: ((AgentActivityUpdate) -> Void)?
  // System automation callback
  var onCommandApprovalRequest: ((String, String?, String?, String, String, String) -> Void)?  // (id, runId, conversationId, command, description, riskLevel)
  var onSecretCredentialRequest: ((String, String?, String?, String, String) -> Void)?
  var onSecretCredentialResolved: ((String, Bool) -> Void)?

  // MARK: - Lifecycle

  init() {
    session = URLSession(configuration: .default)
    NotificationCenter.default.publisher(for: .detachHostedProfileDidSync)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.requestCapabilities(force: true)
        self?.listMediaModels()
        self?.listMCPServers()
        self?.composioIntegrations = []
        self?.composioError = nil
      }
      .store(in: &cancellables)
  }

  // MARK: - Multi-listener Hooks

  func addActivityListener(_ listener: @escaping (String, String?) -> Void) {
    activityListeners.append(listener)
  }

  func addCompletionListener(_ listener: @escaping (String, String?, String?, Int?, Int?) -> Void) {
    completionListeners.append(listener)
  }

  func addErrorListener(_ listener: @escaping (String) -> Void) {
    errorListeners.append(listener)
  }

  func addCreditsListener(_ listener: @escaping (String) -> Void) {
    creditsListeners.append(listener)
  }

  func addChatSentListener(_ listener: @escaping (ChatRequest) -> Void) {
    chatSentListeners.append(listener)
  }

  func addMediaRunStartedListener(_ listener: @escaping (MediaRunStart) -> Void) {
    mediaRunStartedListeners.append(listener)
  }

  func addAgentActivityListener(_ listener: @escaping (AgentActivityUpdate) -> Void) {
    agentActivityListeners.append(listener)
  }

  func addRunCompletionListener(_ listener: @escaping (String?, String) -> Void) {
    runCompletionListeners.append(listener)
  }

  func addRunErrorListener(_ listener: @escaping (String?, String) -> Void) {
    runErrorListeners.append(listener)
  }

  // MARK: - Connection

  func connect() {
    guard !isConnected && !isConnecting else { return }
    isConnecting = true

    let url = ServerConfig.wsURL
    print("🔌 Connecting to local runtime")

    webSocket = session?.webSocketTask(with: url)
    webSocket?.resume()

    // Start receiving - successful receive means we're connected
    receiveMessage()

    // Send a ping to verify connection
    sendPingAndVerify()
  }

  private func sendPingAndVerify() {
    let ping = PingRequest()
    guard let data = try? JSONEncoder().encode(ping),
      let jsonString = String(data: data, encoding: .utf8)
    else { return }

    webSocket?.send(.string(jsonString)) { [weak self] error in
      let weakSelf = self
      Task { @MainActor in
        guard let self = weakSelf else { return }
        self.isConnecting = false
        if let error = error {
          print("❌ Connection failed: \(error.localizedDescription)")
          self.isConnected = false
          self.lastError = error.localizedDescription
        } else {
          print("✅ WebSocket connected!")
          self.isConnected = true
          self.lastError = nil
          self.startPingTimer()

          // Fetch initial data
          self.listQuickActions()
          self.listWorkflows()
          self.listSlashCommands()
          self.listMCPServers()
          self.requestCapabilities()
          // Runtime processes can restart independently of SwiftUI's auth
          // lifecycle. Re-send the active loopback-only session on every
          // connection so Detach Cloud never depends on a prior profile refresh.
          Task {
            await AuthManager.shared.syncProfileToServer()
          }
          self.listConversations()
          if let conversationId = self.currentConversationId {
            self.getConversation(id: conversationId)
          }
        }
      }
    }
  }

  func requestCapabilities(force: Bool = false) {
    guard isConnected else { return }

    if capabilitiesRequestInFlight {
      if force { capabilitiesRefreshQueued = true }
      return
    }

    capabilitiesRequestInFlight = true
    isLoadingCapabilities = true
    capabilitiesTimeoutTask?.cancel()
    capabilitiesTimeoutTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 15_000_000_000)
      guard !Task.isCancelled else { return }
      guard let self, self.capabilitiesRequestInFlight else { return }
      self.capabilitiesRequestInFlight = false
      self.capabilitiesRefreshQueued = false
      self.isLoadingCapabilities = false
      print("⚠️ Capability discovery timed out; keeping the last known provider state")
    }
    sendRawRequest(["type": "capabilities"], label: "capabilities")
  }

  func disconnect() {
    capabilitiesTimeoutTask?.cancel()
    capabilitiesTimeoutTask = nil
    capabilitiesRequestInFlight = false
    capabilitiesRefreshQueued = false
    isLoadingCapabilities = false
    isLoadingMCPServers = false
    pingTimer?.invalidate()
    pingTimer = nil
    webSocket?.cancel(with: .normalClosure, reason: nil)
    webSocket = nil
    isConnected = false
    isConnecting = false
    isStreaming = false
    print("🔌 WebSocket disconnected")
  }

  /// Stop the current streaming request
  func stopStreaming() {
    guard isStreaming else { return }

    // Send stop request to server
    let stopRequest = ["type": "stop_stream"]
    if let data = try? JSONSerialization.data(withJSONObject: stopRequest),
      let jsonString = String(data: data, encoding: .utf8)
    {
      webSocket?.send(.string(jsonString)) { error in
        if let error = error {
          print("❌ Failed to send stop request: \(error.localizedDescription)")
        }
      }
    }

    isStreaming = false
    currentResponse = ""
    print("🛑 Streaming stopped by user")
  }

  // MARK: - Sending Messages

  /// Send a chat message with optional file attachments
  /// If conversationId is nil, starts a new conversation
  /// Detach v2 is local-first; userId is unused unless a future runtime needs it.
  func sendChat(
    text: String, displayText: String? = nil, files: [FileAttachmentRequest] = [],
    conversationId: String? = nil, workspacePath: String? = nil,
    integrations: [String]? = nil, systemPrompt: String? = nil, fastMode: Bool = false,
    userId: String? = nil, zeroDataRetention: Bool? = nil,
    actionId: String? = nil, mcpServerIds: [String]? = nil, skills: [SkillAttachment]? = nil,
    browserTabs: [BrowserTabAttachment]? = nil,
    agent: String? = nil, model: String? = nil, modelSettings: AgentModelSettings? = nil
  ) {
    guard isConnected else {
      lastError = "Not connected to server"
      onError?("Not connected to server")
      return
    }

    // Reset state for new message
    currentResponse = ""
    isStreaming = true
    lastError = nil

    // Use provided conversationId or current one for follow-ups
    let convId = conversationId ?? currentConversationId
    let resolvedAgent = agent ?? DetachSettings.selectedAgent
    let resolvedModel = model ?? DetachSettings.selectedModel(for: resolvedAgent)
    let resolvedModelSettings = modelSettings
      ?? DetachSettings.modelSettings(for: resolvedAgent, model: resolvedModel)

    let request = ChatRequest(
      text: text, displayText: displayText, files: files.isEmpty ? nil : files,
      runId: UUID().uuidString,
      conversationId: convId,
      workspacePath: workspacePath,
      integrations: integrations, systemPrompt: systemPrompt, fastMode: fastMode,
      userId: userId,
      model: resolvedModel,
      agent: resolvedAgent,
      modelSettings: resolvedModelSettings,
      zeroDataRetention: zeroDataRetention,
      actionId: actionId,
      mcpServerIds: mcpServerIds,
      skills: skills,
      browserTabs: browserTabs)

    sendRequest(request, label: "chat")
    onChatSent?(request)
    chatSentListeners.forEach { $0(request) }
  }

  func listMediaModels() {
    guard isConnected else { return }
    sendRequest(ListMediaModelsRequest(), label: "list_media_models")
  }

  func quoteMedia(
    requestId: String,
    model: String,
    prompt: String,
    config: MediaGenerationConfig,
    inputRoles: [String]
  ) {
    guard isConnected else { return }
    sendRequest(
      QuoteMediaRequest(
        requestId: requestId,
        model: model,
        prompt: prompt,
        config: config,
        inputRoles: inputRoles.isEmpty ? nil : inputRoles
      ),
      label: "quote_media"
    )
  }

  func generateMedia(
    prompt: String,
    kind: String,
    model: String,
    config: MediaGenerationConfig,
    inputs: [MediaInputRequest]
  ) {
    guard isConnected else {
      onError?("Not connected to server")
      return
    }
    currentResponse = ""
    isStreaming = true
    lastError = nil
    let runId = UUID().uuidString
    sendRequest(
      GenerateMediaRequest(
        runId: runId,
        kind: kind,
        requestKey: UUID().uuidString,
        prompt: prompt,
        model: model,
        config: config,
        inputs: inputs.isEmpty ? nil : inputs,
        conversationId: currentConversationId
      ),
      label: "generate_media"
    )
    let start = MediaRunStart(runId: runId, prompt: prompt, kind: kind, model: model)
    mediaRunStartedListeners.forEach { $0(start) }
  }

  /// List all conversations
  func listConversations(limit: Int = 50, offset: Int = 0) {
    guard isConnected else { return }
    let request = ListConversationsRequest(limit: limit, offset: offset)
    sendRequest(request, label: "list_conversations")
  }

  /// Get a specific conversation with all its messages
  func getConversation(id: String) {
    guard isConnected else { return }
    let request = GetConversationRequest(conversationId: id)
    sendRequest(request, label: "get_conversation")
  }

  /// Delete a conversation
  func deleteConversation(id: String) {
    guard isConnected else { return }
    let request = DeleteConversationRequest(conversationId: id)
    sendRequest(request, label: "delete_conversation")
  }

  /// Search messages across all conversations
  func searchMessages(query: String, limit: Int = 20) {
    guard isConnected else { return }
    let request = SearchMessagesRequest(query: query, limit: limit)
    sendRequest(request, label: "search")
  }

  /// Edit a message's content
  func editMessage(id: String, content: String) {
    guard isConnected else { return }
    let request = EditMessageRequest(messageId: id, content: content)
    sendRequest(request, label: "edit_message")
  }

  /// Delete a specific message
  func deleteMessage(id: String) {
    guard isConnected else { return }
    let request = DeleteMessageRequest(messageId: id)
    sendRequest(request, label: "delete_message")
  }

  /// Start a new conversation (clears current conversation ID)
  func startNewConversation() {
    currentConversationId = nil
    currentResponse = ""
  }

  /// Load a previous conversation
  func loadConversation(id: String) {
    currentConversationId = id
    if isConnected {
      getConversation(id: id)
    }
  }

  // MARK: - MCP Server Management

  /// List all configured MCP servers
  func listMCPServers() {
    guard isConnected else { return }
    isLoadingMCPServers = true
    let request = ListMCPServersRequest()
    sendRequest(request, label: "list_mcp_servers")
  }

  /// Add a new MCP server
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

  /// Delete an MCP server
  func deleteMCPServer(id: String) {
    guard isConnected else { return }
    let request = DeleteMCPServerRequest(serverId: id)
    sendRequest(request, label: "delete_mcp_server")
  }

  /// Connect to an MCP server
  func connectMCPServer(id: String) {
    guard isConnected else { return }
    let request = ConnectMCPServerRequest(serverId: id)
    sendRequest(request, label: "connect_mcp_server")
  }

  /// Disconnect from an MCP server
  func disconnectMCPServer(id: String) {
    guard isConnected else { return }
    let request = DisconnectMCPServerRequest(serverId: id)
    sendRequest(request, label: "disconnect_mcp_server")
  }

  // MARK: - Composio Integration Management

  /// List available Composio integrations
  func listComposioIntegrations(limit: Int = 10, offset: Int = 0, query: String? = nil) {
    guard isConnected else { return }
    isLoadingComposio = true
    composioError = nil
    let userId = AuthManager.shared.currentUser?.id.uuidString
    let request = ListComposioIntegrationsRequest(
      limit: limit, offset: offset, query: query, userId: userId)
    sendRequest(request, label: "list_composio_integrations")
  }

  /// Connect a Composio account (returns auth URL)
  func connectComposioAccount(toolkit: String, callbackUrl: String? = nil) {
    guard isConnected else { return }
    connectingToolkit = toolkit
    let userId = AuthManager.shared.currentUser?.id.uuidString
    let request = ConnectComposioAccountRequest(
      toolkit: toolkit, userId: userId, callbackUrl: callbackUrl)
    sendRequest(request, label: "connect_composio_account")
  }

  /// List connected Composio accounts
  func listComposioConnections() {
    guard isConnected else { return }
    let userId = AuthManager.shared.currentUser?.id.uuidString
    let request = ListComposioConnectionsRequest(userId: userId)
    sendRequest(request, label: "list_composio_connections")
  }

  /// Disconnect a Composio account
  func disconnectComposioAccount(connectionId: String) {
    guard isConnected else { return }
    let userId = AuthManager.shared.currentUser?.id.uuidString
    let request = DisconnectComposioAccountRequest(connectionId: connectionId, userId: userId)
    sendRequest(request, label: "disconnect_composio_account")
  }

  // MARK: - AI Settings Management

  /// Update AI settings on the server
  func updateAISettings(
    agent: String? = nil, model: String?, imageModel: String?, temperature: Double?, maxSteps: Int?,
    systemPrompt: String?, zeroDataRetention: Bool? = nil
  ) {
    guard isConnected else { return }
    let request = UpdateAISettingsRequest(
      agent: agent,
      model: model,
      imageModel: imageModel,
      temperature: temperature,
      maxSteps: maxSteps,
      systemPrompt: systemPrompt,
      zeroDataRetention: zeroDataRetention
    )
    sendRequest(request, label: "update_ai_settings")
  }

  // MARK: - Quick Actions Management

  /// List all custom quick actions
  func listQuickActions() {
    guard isConnected else { return }
    let request = ListQuickActionsRequest()
    sendRequest(request, label: "list_quick_actions")
  }

  /// Add a new quick action
  func addQuickAction(
    name: String, prompt: String, integrations: [String]?, systemImage: String?, shortcut: String?,
    mcpServerIds: [String]? = nil, skills: [SkillAttachment]? = nil,
    inputPolicy: String? = "optional_selection", executionMode: String? = "run_immediately"
  ) {
    guard isConnected else { return }
    let request = AddQuickActionRequest(
      name: name,
      prompt: prompt,
      integrations: integrations,
      systemImage: systemImage,
      shortcut: shortcut,
      mcpServerIds: mcpServerIds,
      skills: skills,
      inputPolicy: inputPolicy,
      executionMode: executionMode
    )
    sendRequest(request, label: "add_quick_action")
  }

  /// Update an existing quick action
  func updateQuickAction(
    actionId: String, name: String?, prompt: String?, integrations: [String]?,
    systemImage: String?, shortcut: String?, enabled: Bool?, position: Int?,
    mcpServerIds: [String]? = nil, skills: [SkillAttachment]? = nil,
    inputPolicy: String? = nil, executionMode: String? = nil
  ) {
    guard isConnected else { return }
    let request = UpdateQuickActionRequest(
      actionId: actionId,
      name: name,
      prompt: prompt,
      integrations: integrations,
      systemImage: systemImage,
      shortcut: shortcut,
      enabled: enabled,
      position: position,
      mcpServerIds: mcpServerIds,
      skills: skills,
      inputPolicy: inputPolicy,
      executionMode: executionMode
    )
    sendRequest(request, label: "update_quick_action")
  }

  /// Delete a quick action
  func deleteQuickAction(actionId: String) {
    guard isConnected else { return }
    let request = DeleteQuickActionRequest(actionId: actionId)
    sendRequest(request, label: "delete_quick_action")
  }

  // MARK: - Workflow Management

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

  // MARK: - Slash Command Management

  /// List all custom slash commands
  func listSlashCommands() {
    guard isConnected else { return }
    let request = ListSlashCommandsRequest()
    sendRequest(request, label: "list_slash_commands")
  }

  /// Add a new custom slash command
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

  /// Update an existing custom slash command
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

  /// Delete a custom slash command
  func deleteSlashCommand(commandId: String) {
    guard isConnected else { return }
    let request = DeleteSlashCommandRequest(commandId: commandId)
    sendRequest(request, label: "delete_slash_command")
  }

  // MARK: - Memory Management

  /// List all memories with pagination
  func listMemories(limit: Int = 100, offset: Int = 0, completion: @escaping ([Memory]?) -> Void) {
    guard isConnected else {
      completion(nil)
      return
    }
    let request = ListMemoriesRequest(limit: limit, offset: offset)
    // Store callback for response handler
    memoryListCallback = completion
    sendRequest(request, label: "list_memories")
  }

  /// Add a new memory
  func addMemory(
    content: String, category: String = "general", importance: Int = 5,
    completion: @escaping (Bool) -> Void
  ) {
    guard isConnected else {
      completion(false)
      return
    }
    let request = AddMemoryRequest(content: content, category: category, importance: importance)
    memoryAddCallback = completion
    sendRequest(request, label: "add_memory")
  }

  /// Update an existing memory
  func updateMemory(
    id: String, content: String, category: String? = nil, completion: @escaping (Bool) -> Void
  ) {
    guard isConnected else {
      completion(false)
      return
    }
    let request = UpdateMemoryRequest(id: id, content: content, category: category)
    memoryUpdateCallback = completion
    sendRequest(request, label: "update_memory")
  }

  /// Delete a memory
  func deleteMemory(id: String, completion: @escaping (Bool) -> Void) {
    guard isConnected else {
      completion(false)
      return
    }
    let request = DeleteMemoryRequest(id: id)
    memoryDeleteCallback = completion
    sendRequest(request, label: "delete_memory")
  }

  /// Clear all memories
  func clearMemories(completion: @escaping (Bool) -> Void) {
    guard isConnected else {
      completion(false)
      return
    }
    let request = ClearMemoriesRequest()
    memoryClearCallback = completion
    sendRequest(request, label: "clear_memories")
  }

  // Memory callbacks (temporary storage for completion handlers)
  private var memoryListCallback: (([Memory]?) -> Void)?
  private var memoryAddCallback: ((Bool) -> Void)?
  private var memoryUpdateCallback: ((Bool) -> Void)?
  private var memoryDeleteCallback: ((Bool) -> Void)?
  private var memoryClearCallback: ((Bool) -> Void)?

  // MARK: - System Automation

  /// Send command approval response to server
  func sendCommandApprovalResponse(requestId: String, approved: Bool) {
    guard isConnected else { return }
    let response = CommandApprovalResponse(requestId: requestId, approved: approved)
    sendRequest(response, label: "command_approval_response")
  }

  private func sendSecretCommandResult(id: String, ok: Bool, resultJson: String? = nil, error: String? = nil) {
    guard isConnected else { return }
    sendRequest(SecretCommandResult(id: id, ok: ok, resultJson: resultJson, error: error), label: "secret_command_result")
  }

  private func handleSecretCommand(
    id: String,
    command: String,
    credentialId: String?,
    query: String?,
    origin: String?,
    runId: String?,
    conversationId: String?
  ) async {
    do {
      switch command {
      case "secrets.search":
        let result = secretVault.search(query: query ?? "", origin: origin)
        let data = try JSONSerialization.data(withJSONObject: result)
        sendSecretCommandResult(id: id, ok: true, resultJson: String(decoding: data, as: UTF8.self))
      case "secrets.use_browser":
        guard let credentialId, let origin else { throw SecretVaultError.notFound }
        let label = secretVault.credentials.first(where: { $0.id == credentialId })?.label ?? "Saved credential"
        onSecretCredentialRequest?(id, runId, conversationId, label, origin)
        let credential = try await secretVault.authorizeBrowserCredential(
          id: credentialId,
          origin: origin,
          runId: runId,
          conversationId: conversationId)
        let data = try JSONSerialization.data(withJSONObject: [
          "approved": true,
          "username": credential.username,
          "password": credential.password,
        ])
        sendSecretCommandResult(id: id, ok: true, resultJson: String(decoding: data, as: UTF8.self))
        onSecretCredentialResolved?(id, true)
      default:
        sendSecretCommandResult(id: id, ok: false, error: "Unsupported secret command")
      }
    } catch {
      sendSecretCommandResult(id: id, ok: false, error: error.localizedDescription)
      onSecretCredentialResolved?(id, false)
    }
  }

  // MARK: - Private Helpers

  private func sendRequest<T: Encodable>(_ request: T, label: String) {
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

  private func sendRawRequest(_ request: [String: String], label: String) {
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

  private func publishActivity(
    _ status: String,
    toolName: String?,
    event: AgentActivityEvent? = nil,
    runId: String? = nil,
    conversationId: String? = nil
  ) {
    // The runtime supplies the durable conversation ID before a long-running
    // task completes. Retain it here so the workspace can reopen the original
    // live composer instead of constructing a second, history-only panel.
    if let conversationId {
      currentConversationId = conversationId
    }

    let visibleStatus = event?.userFacing == false
      ? nil
      : visibleActivityStatus(status, event: event)
    if let visibleStatus {
      onActivityUpdate?(visibleStatus, toolName)
      activityListeners.forEach { $0(visibleStatus, toolName) }
    }

    // Keep provider lifecycle/debug events out of both user-facing activity surfaces.
    guard event?.userFacing != false,
      let islandStatus = visibleStatus ?? event?.subtitle ?? event?.title
    else { return }
    let update = AgentActivityUpdate(
      runId: runId,
      conversationId: conversationId,
      status: islandStatus,
      toolName: toolName,
      event: event
    )
    onAgentActivityUpdate?(update)
    agentActivityListeners.forEach { $0(update) }
    print("📊 Activity: \(islandStatus)\(toolName != nil ? " (\(toolName!))" : "")")
  }

  private func visibleActivityStatus(_ status: String, event: AgentActivityEvent? = nil) -> String? {
    let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let combined = "\(trimmed) \(event?.title ?? "") \(event?.subtitle ?? "")".lowercased()
    if combined.contains("still working")
      || combined.contains("without a new")
      || combined.contains("no new event")
    {
      return "Working…"
    }
    if event?.action == "think" || combined.contains(" is thinking") {
      return "Thinking…"
    }
    if event?.action == "error" && [
      "network", "connection", "connect", "socket", "timed out", "timeout",
      "fetch failed", "econn", "enotfound", "dns", "temporary", "service unavailable",
      "bad gateway", "gateway timeout", "429", "502", "503", "504"
    ].contains(where: { combined.contains($0) }) {
      return "Retrying…"
    }

    let terminalPattern = #"\b(finished|complete|completed|done)\b"#
    if trimmed.range(of: terminalPattern, options: [.regularExpression, .caseInsensitive]) != nil {
      return nil
    }

    let lifecyclePatterns = [
      #"^Using\s+(Codex|Claude|Grok|fx|OpenCode|Detach Cloud|Detach Hosted|Hosted AI|Agent)\b"#,
      #"^Starting\s+(Codex|Claude|Grok|fx|OpenCode|Detach Cloud|Detach Hosted|Hosted AI)\b"#,
      #"^(Codex|Claude|Grok|fx|OpenCode|Detach Cloud|Detach Hosted|Hosted AI)\s+is\s+thinking\b"#,
      #"^(Codex|Claude|Grok|fx|OpenCode|Detach Cloud|Detach Hosted|Hosted AI)\s+is\s+still\s+working\b"#,
      #"^(Codex|Claude|Grok|fx|OpenCode|Detach Cloud|Detach Hosted|Hosted AI)\s+(thread|session)\s+started\b"#,
      #"^(Codex|Claude|Grok|fx|OpenCode|Detach Cloud|Detach Hosted|Hosted AI)\s+will\s+use\s+MCP\s+servers\b"#,
      #"^Loaded\s+\d+\s+MCP\s+server"#,
      #"^Thinking:\s*"#,
    ]

    if lifecyclePatterns.contains(where: {
      trimmed.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
    }) {
      return nil
    }

    return trimmed
  }

  // MARK: - Receiving Messages

  private func receiveMessage() {
    webSocket?.receive { [weak self] result in
      let weakSelf = self
      Task { @MainActor in
        guard let self = weakSelf else { return }
        switch result {
        case .success(let message):
          self.handleMessage(message)
          // Continue listening
          self.receiveMessage()

        case .failure(let error):
          print("❌ Receive error: \(error.localizedDescription)")
          self.handleConnectionError(error)
        }
      }
    }
  }

  private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
    switch message {
    case .string(let text):
      guard let data = text.data(using: .utf8) else { return }
      if handleDesktopCommand(data) { return }
      let serverMessage = ServerMessage.parse(from: data)
      self.handleServerMessage(serverMessage)

    case .data(let data):
      if handleDesktopCommand(data) { return }
      let serverMessage = ServerMessage.parse(from: data)
      self.handleServerMessage(serverMessage)

    @unknown default:
      break
    }
  }

  private func handleDesktopCommand(_ data: Data) -> Bool {
    guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      message["type"] as? String == "desktop_command",
      let id = message["id"] as? String,
      let command = message["command"] as? String
    else { return false }

    let payload = message["payload"] as? [String: Any] ?? [:]
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let result = try await self.desktopAutomation.execute(command: command, payload: payload)
        self.sendDesktopCommandResult(id: id, result: result)
      } catch {
        self.sendDesktopCommandResult(id: id, error: error.localizedDescription)
      }
    }
    return true
  }

  private func sendDesktopCommandResult(id: String, result: Any? = nil, error: String? = nil) {
    var response: [String: Any] = [
      "type": "desktop_command_result",
      "id": id,
      "ok": error == nil,
    ]
    if let result { response["result"] = result }
    if let error { response["error"] = error }

    guard JSONSerialization.isValidJSONObject(response),
      let data = try? JSONSerialization.data(withJSONObject: response),
      let string = String(data: data, encoding: .utf8)
    else {
      print("❌ Failed to encode desktop command result")
      return
    }

    webSocket?.send(.string(string)) { error in
      if let error { print("❌ Failed to send desktop command result: \(error.localizedDescription)") }
    }
  }

  private func handleServerMessage(_ message: ServerMessage) {
    switch message {
    case .chunk(let text, let isFirst, let timeToFirstChunkMs):
      currentResponse += text
      onChunk?(text)
      if isFirst, let ttfc = timeToFirstChunkMs {
        onFirstChunk?(ttfc)
      }

    case .done(let runId, let conversationId, let messageId, let userMessageId, let tokenCount, let durationMs):
      isStreaming = false
      // Store the conversation ID for follow-up messages
      currentConversationId = conversationId
      onComplete?(conversationId, messageId, userMessageId, tokenCount, durationMs)
      completionListeners.forEach {
        $0(conversationId, messageId, userMessageId, tokenCount, durationMs)
      }
      runCompletionListeners.forEach { $0(runId, conversationId) }
      print(
        "✅ Response complete (conversation: \(conversationId), tokens: \(tokenCount ?? 0), duration: \(durationMs ?? 0)ms)"
      )

    case .error(let errorMessage, let runId):
      lastError = errorMessage
      composioError = errorMessage
      connectingToolkit = nil
      isLoadingMCPServers = false
      isStreaming = false
      onError?(errorMessage)
      errorListeners.forEach { $0(errorMessage) }
      runErrorListeners.forEach { $0(runId, errorMessage) }

    case .creditsExhausted(let message):
      isStreaming = false
      onCreditsExhausted?(message)
      creditsListeners.forEach { $0(message) }
      print("💰 Credits exhausted: \(message)")

    case .pong:
      // Connection verified
      if !isConnected {
        isConnected = true
        print("✅ Connection verified via pong")
      }

    case .capabilities(let agents, let defaultAgent):
      capabilitiesTimeoutTask?.cancel()
      capabilitiesTimeoutTask = nil
      capabilitiesRequestInFlight = false
      let refreshAgain = capabilitiesRefreshQueued
      capabilitiesRefreshQueued = false
      isLoadingCapabilities = refreshAgain
      DetachSettings.migrateLegacyHostedOpenCodeSelection(
        availableAgentIDs: Set(agents.map(\.id))
      )
      agentCapabilities = agents
      if let defaultAgent {
        self.defaultAgent = defaultAgent
      }
      if !agents.contains(where: { $0.id == DetachSettings.selectedAgent && $0.installed }),
        let firstInstalled = agents.first(where: { $0.installed })
      {
        DetachSettings.selectedAgent = firstInstalled.id
      }
      print("🧠 Agent capabilities loaded: \(agents.map { "\($0.displayName):\($0.installed)" }.joined(separator: ", "))")
      if refreshAgain {
        requestCapabilities()
      }

    case .mediaModels(let models):
      mediaModels = models
      onMediaModels?(models)
      print("🎨 Loaded \(models.count) Detach Cloud media models")

    case .mediaQuote(let requestId, let quote):
      onMediaQuote?(requestId, quote)

    case .mediaJob(let runId, let conversationId, let userMessageId, let assistantMessageId, let job):
      currentConversationId = conversationId
      isStreaming = !job.isTerminal
      onMediaJob?(runId, conversationId, userMessageId, assistantMessageId, job)
      if job.isTerminal {
        NotificationCenter.default.post(name: .detachHostedCreditsDidChange, object: nil)
      }
      print("🎞️ Media job \(job.id): \(job.state) \(job.progress)%")

    case .conversationsList(let convs):
      conversations = convs
      onConversationsLoaded?(convs)
      print("📚 Loaded \(convs.count) conversations")

    case .conversation(let conv, let messages):
      currentConversationId = conv.id
      onConversationLoaded?(conv, messages)
      print("💬 Loaded conversation with \(messages.count) messages")

    case .searchResults(let results):
      onSearchResults?(results)
      print("🔍 Found \(results.count) search results")

    case .deleted(let id):
      // Remove from local cache if it's a conversation
      conversations.removeAll { $0.id == id }
      // Clear current if deleted
      if currentConversationId == id {
        currentConversationId = nil
      }
      onDeleted?(id)
      print("🗑️ Deleted: \(id)")

    case .updated(let id):
      onUpdated?(id)
      print("✏️ Updated: \(id)")

    // MCP messages
    case .mcpServerAdded(let server):
      mcpServers.append(server)
      print("🔧 MCP server added: \(server.name)")
      listMCPServers()  // Refresh list

    case .mcpServersList(let servers):
      mcpServers = servers
      isLoadingMCPServers = false
      onMCPServersLoaded?(servers)
      print("🔧 Loaded \(servers.count) MCP servers")

    case .mcpServerDeleted(let serverId):
      mcpServers.removeAll { $0.id == serverId }
      print("🔧 MCP server deleted: \(serverId)")
      listMCPServers()

    case .mcpServerConnected(let status):
      if let index = mcpServers.firstIndex(where: { $0.id == status.id }) {
        mcpServers[index].status = status
      }
      print("🔧 MCP server connected: \(status.name)")
      listMCPServers()

    case .mcpServerDisconnected(let serverId):
      if let index = mcpServers.firstIndex(where: { $0.id == serverId }) {
        mcpServers[index].status = nil
      }
      print("🔧 MCP server disconnected: \(serverId)")
      listMCPServers()

    case .mcpToolsList(let tools):
      print("🔧 MCP tools: \(tools.map { $0.name })")

    case .mcpServerUpdated(let server):
      if let index = mcpServers.firstIndex(where: { $0.id == server.id }) {
        mcpServers[index] = server
      }
      print("🔧 MCP server updated: \(server.name)")
      listMCPServers()

    // Composio messages
    case .composioIntegrations(
      let configured, let integrations, let total, let hasMore, let limit, let offset, let error):
      isLoadingComposio = false
      composioError = error
      connectingToolkit = nil

      if (offset ?? 0) == 0 {
        composioIntegrations = integrations
      } else {
        // Append unique newcomers
        let existingIds = Set(composioIntegrations.map { $0.id })
        let uniqueNew = integrations.filter { !existingIds.contains($0.id) }
        composioIntegrations.append(contentsOf: uniqueNew)
      }

      self.totalComposioIntegrations = total ?? 0
      self.hasMoreComposioIntegrations = hasMore ?? false

      onComposioIntegrations?(configured, integrations, total, hasMore, limit, offset, error)
      print(
        "🔌 Composio integrations: \(integrations.count) available, total: \(total ?? 0), hasMore: \(hasMore ?? false)"
      )

    case .composioAuthUrl(let url, let toolkit, let connectionId):
      if let authUrl = URL(string: url) {
        #if os(macOS)
          NSWorkspace.shared.open(authUrl)
          print("🌐 Opened auth URL for \(toolkit)")
        #endif
      }
      onComposioAuthUrl?(url, toolkit, connectionId)
      print("🔌 Composio auth URL for \(toolkit)")

    case .composioConnections(let connections):
      onComposioConnections?(connections)
      print("🔌 Composio connections: \(connections.count)")

    case .composioConnected(let toolkit, let connectionId, let status):
      connectingToolkit = nil
      listComposioIntegrations()  // Refresh the whole list to show "Connected" status
      onComposioConnected?(toolkit, connectionId, status)
      print("✅ Composio connected: \(toolkit) (\(connectionId))")

    case .composioDisconnected(let connectionId):
      listComposioIntegrations()  // Refresh to show "Available"
      onComposioDisconnected?(connectionId)
      print("🔌 Composio disconnected: \(connectionId)")

    // Quick Actions messages
    case .quickActionsList(let actions):
      customQuickActions = actions
      onQuickActionsList?(actions)
      print("⚡ Loaded \(actions.count) quick actions")

    case .quickActionAdded(let action):
      customQuickActions.append(action)
      onQuickActionAdded?(action)
      print("⚡ Quick action added: \(action.title)")

    case .quickActionUpdated(let action):
      if let index = customQuickActions.firstIndex(where: { $0.id == action.id }) {
        customQuickActions[index] = action
      }
      onQuickActionUpdated?(action)
      print("⚡ Quick action updated: \(action.title)")

    case .quickActionDeleted(let actionId):
      customQuickActions.removeAll { $0.id == actionId }
      onQuickActionDeleted?(actionId)
      print("⚡ Quick action deleted: \(actionId)")

    case .actionLearningStarted(_, let actionName):
      let name = actionName.isEmpty ? "this action" : actionName
      publishActivity("Learning \(name) for faster future runs", toolName: "Action learning")
      print("🧠 Learning action: \(name)")

    case .actionLearningCompleted(let action):
      if action.kind == "workflow" {
        if let index = workflows.firstIndex(where: { $0.id == action.id }) {
          workflows[index] = action
        }
        onWorkflowUpdated?(action)
      } else {
        if let index = customQuickActions.firstIndex(where: { $0.id == action.id }) {
          customQuickActions[index] = action
        }
        onQuickActionUpdated?(action)
      }
      print("🧠 Learned action skill: \(action.title)")

    case .workflowsList(let items):
      workflows = items
      onWorkflowsList?(items)
      print("⚙️ Loaded \(items.count) workflows")

    case .workflowAdded(let workflow):
      workflows.append(workflow)
      onWorkflowAdded?(workflow)
      print("⚙️ Workflow added: \(workflow.title)")

    case .workflowUpdated(let workflow):
      if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
        workflows[index] = workflow
      }
      onWorkflowUpdated?(workflow)
      print("⚙️ Workflow updated: \(workflow.title)")

    case .workflowDeleted(let actionId):
      workflows.removeAll { $0.id == actionId }
      onWorkflowDeleted?(actionId)
      print("⚙️ Workflow deleted: \(actionId)")

    case .imageGenerated(let image, let prompt):
      onImageGenerated?(image, prompt)
      print("🖼️ Received generated image")

    // Slash command messages
    case .slashCommandsList(let commands):
      customSlashCommands = commands
      onSlashCommandsList?(commands)
      print("⌨️ Loaded \(commands.count) custom slash commands")

    case .slashCommandAdded(let command):
      customSlashCommands.append(command)
      onSlashCommandAdded?(command)
      print("⌨️ Custom slash command added: \(command.command)")

    case .slashCommandUpdated(let command):
      if let index = customSlashCommands.firstIndex(where: { $0.id == command.id }) {
        customSlashCommands[index] = command
      }
      onSlashCommandUpdated?(command)
      print("⌨️ Custom slash command updated: \(command.command)")

    case .slashCommandDeleted(let commandId):
      customSlashCommands.removeAll { $0.id == commandId }
      onSlashCommandDeleted?(commandId)
      print("⌨️ Custom slash command deleted: \(commandId)")

    // Memory messages
    case .memoriesList(let memories, _):
      memoryListCallback?(memories)
      memoryListCallback = nil
      print("🧠 Loaded \(memories.count) memories")

    case .memoryAdded(_):
      memoryAddCallback?(true)
      memoryAddCallback = nil
      print("🧠 Memory added")

    case .memoryUpdated(let success, _):
      memoryUpdateCallback?(success)
      memoryUpdateCallback = nil
      print("🧠 Memory updated: \(success)")

    case .memoryDeleted(let success, _):
      memoryDeleteCallback?(success)
      memoryDeleteCallback = nil
      print("🧠 Memory deleted: \(success)")

    case .memoriesCleared(let success):
      memoryClearCallback?(success)
      memoryClearCallback = nil
      print("🧠 All memories cleared: \(success)")

    case .unknown:
      print("⚠️ Received unknown message type")

    case .activity(let status, let toolName, let event, let runId, let conversationId):
      publishActivity(status, toolName: toolName, event: event, runId: runId, conversationId: conversationId)

    case .commandApprovalRequest(let id, let runId, let conversationId, let command, let description, let riskLevel):
      onCommandApprovalRequest?(id, runId, conversationId, command, description, riskLevel)
      print("⚠️ Command approval request: \(command) (risk: \(riskLevel))")

    case .secretCommand(let id, let command, let credentialId, let query, let origin, _, _, let runId, let conversationId):
      Task { @MainActor [weak self] in
        await self?.handleSecretCommand(id: id, command: command, credentialId: credentialId, query: query, origin: origin, runId: runId, conversationId: conversationId)
      }
    }
  }

  private func handleConnectionError(_ error: Error) {
    isConnected = false
    isConnecting = false
    isLoadingMCPServers = false
    isStreaming = false
    lastError = error.localizedDescription
    onError?(error.localizedDescription)

    // Try to reconnect after delay
    print("🔄 Will retry in 3 seconds...")
    Task {
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      connect()
    }
  }

  // MARK: - Keep Alive

  private func startPingTimer() {
    pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      let weakSelf = self
      Task { @MainActor in
        weakSelf?.sendPing()
      }
    }
  }

  private func sendPing() {
    guard isConnected else { return }

    let ping = PingRequest()
    guard let data = try? JSONEncoder().encode(ping),
      let jsonString = String(data: data, encoding: .utf8)
    else { return }

    webSocket?.send(.string(jsonString)) { _ in }
  }
}
