import Auth
import Combine
import Foundation

#if os(macOS)
  import AppKit
#endif

/// Manages WebSocket connection to the AI server
@MainActor
class WebSocketManager: ObservableObject {
  var onCommandApprovalResolved: ((String, String) -> Void)?
  @Published var lastContextSummary: ChatContextSummary?

  // MARK: - Published Properties

  @Published var isConnected = false
  @Published var currentResponse = ""
  @Published var isStreaming = false
  @Published var lastError: String?
  @Published var currentConversationId: String?
  var currentConversationTitle: String?
  var conversationTitleCache = ConversationTitleCache()
  let providerHistory = ProviderHistoryState()
  @Published var currentConversation: Conversation?
  @Published var conversationBranchState: ConversationBranchState?
  var onProviderSession: ((Conversation) -> Void)?
  var onConversationTitleUpdated: ((String, String) -> Void)?
  var activeChatRequest: ChatRequest?
  var routingTask: Task<Void, Never>?
  var routingGeneration: UUID?
  var autoRoutedChoice: RouterPreset?
  var isStoppingRun = false
  var isResumingDetachedRun = false
  var onRunStopRequested: ((String) -> Void)?
  var onRunConnectionLost: ((String, String) -> Void)?
  @Published var conversations: [Conversation] = []
  @Published var hasMoreConversations = false
  @Published var isLoadingMoreConversations = false
  var nextConversationOffset = 0
  @Published var mcpServers: [MCPServer] = []
  @Published var isLoadingMCPServers = false
  @Published var workflows: [SavedWorkflow] = []
  @Published var customSlashCommands: [CustomSlashCommand] = []
  @Published var agentCapabilities: [AgentCapability] = []
  @Published var isLoadingCapabilities = false
  @Published var defaultAgent: String = DetachSettings.defaultAgent

  // Composio Integration State
  @Published var composioIntegrations: [ComposioIntegration] = []
  @Published var isLoadingComposio = false
  @Published var composioError: String? = nil
  @Published var connectingToolkit: String? = nil
  @Published var hasMoreComposioIntegrations = false
  @Published var totalComposioIntegrations = 0

  // MARK: - Private Properties

  var webSocket: URLSessionWebSocketTask?
  var session: URLSession?
  var conversationLoadTask: Task<Void, Never>?
  var conversationLoadID: UUID?
  var pingTimer: Timer?
  var isConnecting = false
  let desktopAutomation = DesktopAutomationService.shared
  var desktopSessionIDs = Set<String>()
  let secretVault = SecretVault.shared
  var activityListeners: [(String, String?) -> Void] = []
  var completionListeners: [(String, String?, String?, Int?, Int?) -> Void] = []
  var errorListeners: [(String) -> Void] = []
  var chatSentListeners: [(ChatRequest) -> Void] = []
  var agentActivityListeners: [(AgentActivityUpdate) -> Void] = []
  var runCompletionListeners: [(String?, String) -> Void] = []
  var runErrorListeners: [(String?, String) -> Void] = []
  var cancellables = Set<AnyCancellable>()
  var capabilitiesRequestInFlight = false
  var capabilitiesRefreshQueued = false
  var capabilitiesTimeoutTask: Task<Void, Never>?

  // MARK: - Callbacks

  var onChunk: ((String) -> Void)?
  var onFirstChunk: ((Int) -> Void)?  // Time to first chunk in ms
  var onComplete: ((String, String?, String?, Int?, Int?) -> Void)?  // (conversationId, assistantId, userId, tokenCount, durationMs)
  var onChatSent: ((ChatRequest) -> Void)?
  var onError: ((String) -> Void)?
  var onConversationsLoaded: (([Conversation]) -> Void)?
  var onConversationLoaded: ((Conversation, [Message]) -> Void)?
  var conversationLoadedListeners: [(Conversation, [Message]) -> Void] = []
  var onSearchResults: (([SearchResult]) -> Void)?
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
  // Workflow callbacks
  var onWorkflowsList: (([SavedWorkflow]) -> Void)?
  var onWorkflowAdded: ((SavedWorkflow) -> Void)?
  var onWorkflowUpdated: ((SavedWorkflow) -> Void)?
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
    NotificationCenter.default.publisher(for: .detachProfileDidSync)
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.requestCapabilities(force: true)
        self?.listMCPServers()
        self?.composioIntegrations = []
        self?.composioError = nil
      }
      .store(in: &cancellables)
  }

  // MARK: - Multi-listener Hooks

  func addConversationLoadedListener(_ listener: @escaping (Conversation, [Message]) -> Void) {
    conversationLoadedListeners.append(listener)
  }

  func addActivityListener(_ listener: @escaping (String, String?) -> Void) {
    activityListeners.append(listener)
  }

  func addCompletionListener(_ listener: @escaping (String, String?, String?, Int?, Int?) -> Void) {
    completionListeners.append(listener)
  }

  func addErrorListener(_ listener: @escaping (String) -> Void) {
    errorListeners.append(listener)
  }

  func addChatSentListener(_ listener: @escaping (ChatRequest) -> Void) {
    chatSentListeners.append(listener)
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

  func sendPingAndVerify() {
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
          self.listWorkflows()
          self.listSlashCommands()
          self.listMCPServers()
          self.requestCapabilities()
          // Runtime processes can restart independently of SwiftUI's auth
          // lifecycle. Re-send the active loopback-only session on every
          // connection so integrations receive the current profile.
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
    endDesktopSessions()
    cancelAutoRouting()
    cancelConversationLoad()
    providerHistory.connectionLost()
    dismissAgentQuestions()
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
    if cancelAutoRouting() { return }
    guard isStreaming else { return }
    dismissAgentQuestions()
    if let runId = activeChatRequest?.runId {
      isStoppingRun = true
      onRunStopRequested?(runId)
    }

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

  /// List all conversations

  /// Get a specific conversation with all its messages

  /// Delete a conversation

  /// Search messages across all conversations

  /// Edit a message's content

  /// Delete a specific message

  /// Start a new conversation (clears current conversation ID)

  /// Load a previous conversation

  // MARK: - MCP Server Management

  /// List all configured MCP servers

  /// Add a new MCP server

  /// Delete an MCP server

  /// Connect to an MCP server

  /// Disconnect from an MCP server

  // MARK: - Composio Integration Management

  /// List available Composio integrations

  /// Connect a Composio account (returns auth URL)

  /// List connected Composio accounts

  /// Disconnect a Composio account

  // MARK: - AI Settings Management

  /// Update AI settings on the server

  // MARK: - Workflow Management

  // MARK: - Slash Command Management

  /// List all custom slash commands

  /// Add a new custom slash command

  /// Update an existing custom slash command

  /// Delete a custom slash command

  // MARK: - System Automation

  /// Send command approval response to server
  func sendCommandApprovalResponse(requestId: String, approved: Bool) {
    guard isConnected else { return }
    let response = CommandApprovalResponse(requestId: requestId, approved: approved)
    sendRequest(response, label: "command_approval_response")
  }

  func sendSecretCommandResult(id: String, ok: Bool, resultJson: String? = nil, error: String? = nil) {
    guard isConnected else { return }
    sendRequest(SecretCommandResult(id: id, ok: ok, resultJson: resultJson, error: error), label: "secret_command_result")
  }

  func handleSecretCommand(
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

  func sendQuestionAnswer(_ response: AgentQuestionResponse) {
    guard isConnected else { dismissAgentQuestions(); return }
    sendRequest(response, label: "agent_question_response")
  }

  // MARK: - Receiving Messages

  func receiveMessage() {
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

  func handleMessage(_ message: URLSessionWebSocketTask.Message) {
    switch message {
    case .string(let text):
      guard let data = text.data(using: .utf8) else { return }
      if handleConversationBranches(data) || handleProviderHistory(data) || handleConversationTitle(data) || handleAgentQuestion(data) || handleDesktopCommand(data) { return }
      let serverMessage = ServerMessage.parse(from: data)
      self.handleServerMessage(serverMessage)

    case .data(let data):
      if handleConversationBranches(data) || handleProviderHistory(data) || handleConversationTitle(data) || handleAgentQuestion(data) || handleDesktopCommand(data) { return }
      let serverMessage = ServerMessage.parse(from: data)
      self.handleServerMessage(serverMessage)

    @unknown default:
      break
    }
  }

  func handleConversationTitle(_ data: Data) -> Bool {
    guard let update = ConversationTitleUpdate.parse(data) else { return false }
    conversationTitleCache.record(update)
    conversations = conversations.map { $0.id == update.conversationId ? $0.named(update.title) : $0 }
    if currentConversationId == update.conversationId { currentConversationTitle = update.title }
    onConversationTitleUpdated?(update.conversationId, update.title)
    return true
  }

  func handleDesktopCommand(_ data: Data) -> Bool {
    guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      message["type"] as? String == "desktop_command",
      let id = message["id"] as? String,
      let command = message["command"] as? String
    else { return false }

    let payload = message["payload"] as? [String: Any] ?? [:]
    if let sessionID = payload["_sessionId"] as? String {
      if command == "desktop.end_session" { desktopSessionIDs.remove(sessionID) }
      else { desktopSessionIDs.insert(sessionID) }
      desktopAutomation.stopHandlers[sessionID] = { [weak self] in
        let object: [String: Any] = ["type": "desktop_stop_requested", "runId": sessionID]
        if let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) {
          self?.webSocket?.send(.string(text)) { _ in }
        }
      }
    }
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

  func sendDesktopCommandResult(id: String, result: Any? = nil, error: String? = nil) {
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

  func endDesktopSessions() {
    for id in desktopSessionIDs { desktopAutomation.endSession(id) }
    desktopSessionIDs.removeAll()
  }

  func handleConnectionError(_ error: Error) {
    endDesktopSessions()
    cancelAutoRouting()
    cancelConversationLoad()
    providerHistory.connectionLost()
    dismissAgentQuestions()
    let hadActiveRun = isStreaming || isStoppingRun
    isStoppingRun = false
    if let runId = activeChatRequest?.runId, hadActiveRun {
      onRunConnectionLost?(runId, error.localizedDescription)
    }
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

  func startPingTimer() {
    pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      let weakSelf = self
      Task { @MainActor in
        weakSelf?.sendPing()
      }
    }
  }

  func sendPing() {
    guard isConnected else { return }

    let ping = PingRequest()
    guard let data = try? JSONEncoder().encode(ping),
      let jsonString = String(data: data, encoding: .utf8)
    else { return }

    webSocket?.send(.string(jsonString)) { _ in }
  }
}
