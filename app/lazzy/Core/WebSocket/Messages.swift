import Foundation
import Combine

// MARK: - Client → Server Messages

struct AgentModelSettings: Codable, Equatable {
  let reasoningEffort: String?

  init(reasoningEffort: String? = nil) {
    self.reasoningEffort = reasoningEffort
  }
}

struct ChatRequest: Codable {
  var type: String = "chat"
  /// A client-generated ID that lets the detached island follow this run while the chat is hidden.
  let runId: String?
  /// Only Debug app builds enable the runtime's exact-prompt demo scenarios.
  let demoMode: Bool?
  let text: String
  let displayText: String?
  let files: [FileAttachmentRequest]?
  let conversationId: String?
  /// The folder selected in the floating composer for this agent run.
  let workspacePath: String?
  let integrations: [String]?
  let systemPrompt: String?
  let composerMode: ComposerMode?
  let slashCommandId: String?
  let fastMode: Bool?
  let userId: String?  // Supabase user ID for usage billing
  let model: String?  // Optional model override for per-request model selection
  let modelSettings: AgentModelSettings?
  let agent: String?  // Local agent id, e.g. "codex", "claude", or "grok"
  let zeroDataRetention: Bool?  // Optional flag to enable/disable zero data retention
  let actionId: String?
  /// Explicit composer-selected MCP capabilities. An empty array means no MCP capability is attached.
  let mcpServerIds: [String]?
  /// Skills selected in the composer. The runtime validates paths before loading their instructions.
  let skills: [SkillAttachment]?
  /// Chrome tabs explicitly selected from the composer attachment menu.
  let browserTabs: [BrowserTabAttachment]?

  init(
    text: String, displayText: String? = nil, files: [FileAttachmentRequest]? = nil,
    runId: String? = nil,
    conversationId: String? = nil,
    workspacePath: String? = nil,
    integrations: [String]? = nil, systemPrompt: String? = nil, composerMode: ComposerMode? = nil,
    slashCommandId: String? = nil,
    fastMode: Bool = false,
    userId: String? = nil, model: String? = nil, agent: String? = nil,
    modelSettings: AgentModelSettings? = nil,
    zeroDataRetention: Bool? = nil, actionId: String? = nil, mcpServerIds: [String]? = nil,
    skills: [SkillAttachment]? = nil, browserTabs: [BrowserTabAttachment]? = nil
  ) {
    self.runId = runId
    #if DEBUG
      self.demoMode = true
    #else
      self.demoMode = nil
    #endif
    self.text = text
    self.displayText = displayText
    self.files = files
    self.conversationId = conversationId
    self.workspacePath = workspacePath
    self.integrations = integrations
    self.systemPrompt = systemPrompt
    self.composerMode = composerMode
    self.slashCommandId = slashCommandId
    self.fastMode = fastMode ? true : nil  // Only send if true to save bandwidth
    self.userId = userId
    self.model = model
    self.modelSettings = modelSettings
    self.agent = agent
    self.zeroDataRetention = zeroDataRetention
    self.actionId = actionId
    self.mcpServerIds = mcpServerIds
    self.skills = skills
    self.browserTabs = browserTabs
  }
}

struct FileAttachmentRequest: Codable, Equatable {
  let path: String
  let mimeType: String
}

struct BrowserTabAttachment: Codable, Equatable, Identifiable {
  let id: Int
  let windowId: Int?
  let active: Bool
  let title: String
  let url: String

  init(id: Int, windowId: Int? = nil, active: Bool = false, title: String, url: String) {
    self.id = id
    self.windowId = windowId
    self.active = active
    self.title = title
    self.url = url
  }
}

struct MediaGenerationConfig: Codable, Equatable {
  var aspectRatio: String?
  var resolution: String?
  var duration: Int?
  var audio: Bool?
  var outputFormat: String?
}

struct MediaInputRequest: Codable, Equatable {
  let path: String
  let mimeType: String
  let role: String
}

struct GenerateMediaRequest: Codable {
  var type: String = "generate_media"
  let runId: String
  /// Only Debug app builds enable the runtime's local image/video demo scenarios.
  #if DEBUG
    let demoMode: Bool? = true
  #else
    let demoMode: Bool? = nil
  #endif
  let kind: String
  let requestKey: String
  let prompt: String
  let model: String
  let config: MediaGenerationConfig
  let inputs: [MediaInputRequest]?
  let conversationId: String?
}

struct MediaRunStart {
  let runId: String
  let prompt: String
  let kind: String
  let model: String
}

struct ListMediaModelsRequest: Codable {
  var type: String = "list_media_models"
}

struct QuoteMediaRequest: Codable {
  var type: String = "quote_media"
  let requestId: String
  let model: String
  let prompt: String
  let config: MediaGenerationConfig
  let inputRoles: [String]?
}

struct MediaConfigOption: Codable, Identifiable, Equatable {
  let id: String
  let label: String
}

struct MediaModelCapability: Codable, Identifiable, Equatable {
  let id: String
  let displayName: String
  let kind: String
  let description: String?
  let aspectRatios: [MediaConfigOption]
  let resolutions: [MediaConfigOption]
  let durations: [Int]?
  let supportsAudio: Bool
  let outputFormats: [MediaConfigOption]
  let defaults: MediaGenerationConfig
  let inputRoles: [String]
  let maxInputs: Int
  let maxInputsByRole: [String: Int]?
}

struct MediaCreditAmount: Codable, Equatable {
  let kieCredits: String
  let detachCredits: String
}

struct MediaQuote: Codable, Equatable {
  let kieCredits: String?
  let detachCredits: String?
  let summary: String?
}

struct MediaJobError: Codable, Equatable {
  let code: String
  let message: String
}

struct GeneratedMediaAsset: Codable, Identifiable, Equatable {
  let id: String
  let kind: String
  let mimeType: String
  let url: String
  let byteSize: Int?
  let width: Int?
  let height: Int?
  let durationSeconds: Double?
}

struct MediaJob: Codable, Identifiable, Equatable {
  let id: String
  let kind: String
  let model: String
  let state: String
  let progress: Int
  let prompt: String?
  let config: MediaGenerationConfig
  let quote: MediaCreditAmount?
  let actual: MediaCreditAmount?
  let error: MediaJobError?
  let assets: [GeneratedMediaAsset]
  let createdAt: String?
  let updatedAt: String?

  var isTerminal: Bool {
    state == "succeeded" || state == "failed" || state == "reconciliation_required"
  }
}

struct MessagePart: Codable, Equatable {
  let type: String
  let text: String?
  let job: MediaJob?
}

/// A user-selected instruction set from an installed local skill.
/// Only the display metadata and the local SKILL.md path cross the socket; the runtime
/// re-reads and validates the file before it is included in an agent prompt.
struct SkillAttachment: Codable, Identifiable, Equatable, Hashable {
  let id: String
  let name: String
  let path: String
  let summary: String?
}

struct PingRequest: Codable {
  var type: String = "ping"
}

struct SecretCommandResult: Codable {
  var type: String = "secret_command_result"
  let id: String
  let ok: Bool
  let resultJson: String?
  let error: String?
}

// New: List conversations request
struct ListConversationsRequest: Codable {
  var type: String = "list_conversations"
  let limit: Int?
  let offset: Int?

  init(limit: Int? = 50, offset: Int? = 0) {
    self.limit = limit
    self.offset = offset
  }
}

// New: Get single conversation with messages
struct GetConversationRequest: Codable {
  var type: String = "get_conversation"
  let conversationId: String
}

// New: Delete conversation
struct DeleteConversationRequest: Codable {
  var type: String = "delete_conversation"
  let conversationId: String
}

// New: Search messages
struct SearchMessagesRequest: Codable {
  var type: String = "search"
  let query: String
  let limit: Int?

  init(query: String, limit: Int? = 20) {
    self.query = query
    self.limit = limit
  }
}

// New: Edit message content
struct EditMessageRequest: Codable {
  var type: String = "edit_message"
  let messageId: String
  let content: String
}

// New: Delete message
struct DeleteMessageRequest: Codable {
  var type: String = "delete_message"
  let messageId: String
}

// MARK: - MCP Server Messages

struct AddMCPServerRequest: Codable {
  var type: String = "add_mcp_server"
  let name: String
  let transport: String  // "stdio", "sse", or "http"
  let command: String?
  let args: [String]?
  let url: String?
  let headers: [String: String]?
  let env: [String: String]?
  let enabled: Bool?
}

struct ListMCPServersRequest: Codable {
  var type: String = "list_mcp_servers"
}

struct DeleteMCPServerRequest: Codable {
  var type: String = "delete_mcp_server"
  let serverId: String
}

struct ConnectMCPServerRequest: Codable {
  var type: String = "connect_mcp_server"
  let serverId: String
}

struct DisconnectMCPServerRequest: Codable {
  var type: String = "disconnect_mcp_server"
  let serverId: String
}

struct ListMCPToolsRequest: Codable {
  var type: String = "list_mcp_tools"
}

// MARK: - Composio Integration Messages

struct ListComposioIntegrationsRequest: Codable {
  var type: String = "list_composio_integrations"
  let limit: Int?
  let offset: Int?
  let query: String?
  let userId: String?

  init(limit: Int? = 10, offset: Int? = 0, query: String? = nil, userId: String? = nil) {
    self.limit = limit
    self.offset = offset
    self.query = query
    self.userId = userId
  }
}

struct ConnectComposioAccountRequest: Codable {
  var type: String = "connect_composio_account"
  let toolkit: String  // e.g., "gmail", "slack", "github"
  let userId: String?
  let callbackUrl: String?

  init(toolkit: String, userId: String? = nil, callbackUrl: String? = nil) {
    self.toolkit = toolkit
    self.userId = userId
    self.callbackUrl = callbackUrl
  }
}

struct ListComposioConnectionsRequest: Codable {
  var type: String = "list_composio_connections"
  let userId: String?
}

struct DisconnectComposioAccountRequest: Codable {
  var type: String = "disconnect_composio_account"
  let connectionId: String
  let userId: String?
}

// MARK: - AI Settings Messages

struct UpdateAISettingsRequest: Codable {
  var type: String = "update_ai_settings"
  let agent: String?
  let model: String?
  let imageModel: String?
  let temperature: Double?
  let maxSteps: Int?
  let systemPrompt: String?
  let zeroDataRetention: Bool?
}

// MARK: - Quick Actions Messages

struct ListQuickActionsRequest: Codable {
  var type: String = "list_quick_actions"
}

struct AddQuickActionRequest: Codable {
  var type: String = "add_quick_action"
  let name: String
  let prompt: String
  let integrations: [String]?
  let systemImage: String?
  let shortcut: String?
  let mcpServerIds: [String]?
  let skills: [SkillAttachment]?
  let inputPolicy: String?
  let executionMode: String?
}

struct UpdateQuickActionRequest: Codable {
  var type: String = "update_quick_action"
  let actionId: String
  let name: String?
  let prompt: String?
  let integrations: [String]?
  let systemImage: String?
  let shortcut: String?
  let enabled: Bool?
  let position: Int?
  let mcpServerIds: [String]?
  let skills: [SkillAttachment]?
  let inputPolicy: String?
  let executionMode: String?
}

struct DeleteQuickActionRequest: Codable {
  var type: String = "delete_quick_action"
  let actionId: String
}

struct ListWorkflowsRequest: Codable {
  var type: String = "list_workflows"
}

struct AddWorkflowRequest: Codable {
  var type: String = "add_workflow"
  let name: String
  let prompt: String
  let systemImage: String?
  let shortcut: String?
  let mcpServerIds: [String]?
  let skills: [SkillAttachment]?
  let inputPolicy: String?
  let executionMode: String?
}

struct UpdateWorkflowRequest: Codable {
  var type: String = "update_workflow"
  let actionId: String
  let name: String?
  let prompt: String?
  let systemImage: String?
  let shortcut: String?
  let enabled: Bool?
  let position: Int?
  let mcpServerIds: [String]?
  let skills: [SkillAttachment]?
  let inputPolicy: String?
  let executionMode: String?
}

struct DeleteWorkflowRequest: Codable {
  var type: String = "delete_workflow"
  let actionId: String
}

// MARK: - Slash Command Messages

struct ListSlashCommandsRequest: Codable {
  var type: String = "list_slash_commands"
}

struct AddSlashCommandRequest: Codable {
  var type: String = "add_slash_command"
  let command: String
  let title: String
  let subtitle: String?
  let systemImage: String?
  let replacementText: String?
  let promptInstruction: String?
  let mode: ComposerMode?
}

struct UpdateSlashCommandRequest: Codable {
  var type: String = "update_slash_command"
  let commandId: String
  let command: String?
  let title: String?
  let subtitle: String?
  let systemImage: String?
  let replacementText: String?
  let promptInstruction: String?
  let mode: ComposerMode?
  let enabled: Bool?
  let position: Int?
}

struct DeleteSlashCommandRequest: Codable {
  var type: String = "delete_slash_command"
  let commandId: String
}

struct AgentCapability: Codable, Identifiable, Equatable {
  let id: String
  let displayName: String
  let installed: Bool
  let executablePath: String?
  let authHint: String?
  let models: [AgentModelCapability]
  let defaultModel: String?
}

struct AgentModelCapability: Codable, Identifiable, Equatable {
  let id: String
  let displayName: String
  let reasoningEfforts: [String]?
  let defaultReasoningEffort: String?
  let reasoningLabel: String?
}

// MARK: - Memory Messages

struct ListMemoriesRequest: Codable {
  var type: String = "list_memories"
  let limit: Int?
  let offset: Int?

  init(limit: Int? = 100, offset: Int? = 0) {
    self.limit = limit
    self.offset = offset
  }
}

struct AddMemoryRequest: Codable {
  var type: String = "add_memory"
  let content: String
  let category: String?
  let importance: Int?

  init(content: String, category: String? = "general", importance: Int? = 5) {
    self.content = content
    self.category = category
    self.importance = importance
  }
}

struct UpdateMemoryRequest: Codable {
  var type: String = "update_memory"
  let id: String
  let content: String
  let category: String?
}

struct DeleteMemoryRequest: Codable {
  var type: String = "delete_memory"
  let id: String
}

struct ClearMemoriesRequest: Codable {
  var type: String = "clear_memories"
}

// MARK: - System Automation Messages

struct CommandApprovalResponse: Codable {
  var type: String = "command_approval_response"
  let requestId: String
  let approved: Bool
}

// MARK: - Composio Data Models

struct ComposioIntegration: Codable, Identifiable {
  let id: String
  let name: String
  let description: String
  let icon: String
  let connected: Bool
  let connectionId: String?
}

struct ComposioConnection: Codable, Identifiable {
  let id: String
  let toolkit: String
  let status: String
  let connectedAt: String
}

// MARK: - MCP Data Models

struct MCPServer: Codable, Identifiable {
  let id: String
  let name: String
  let transport: String
  let command: String?
  let args: [String]?
  let url: String?
  let headers: [String: String]?
  let env: [String: String]?
  let enabled: Bool
  let created_at: Int
  let updated_at: Int
  var status: MCPServerStatus?
}

struct MCPServerStatus: Codable {
  let id: String
  let name: String
  let connected: Bool
  let tools: [MCPTool]?
  let error: String?
}

struct MCPTool: Codable, Identifiable {
  let name: String
  let description: String?

  var id: String { name }
}

enum ServerMessage {
  case chunk(text: String, isFirst: Bool, timeToFirstChunkMs: Int?)
  case done(
    runId: String?, conversationId: String, messageId: String?, userMessageId: String?, tokenCount: Int?,
    durationMs: Int?)
  case error(message: String, runId: String?)
  case creditsExhausted(message: String)
  case pong
  case capabilities(agents: [AgentCapability], defaultAgent: String?)
  case mediaModels(models: [MediaModelCapability])
  case mediaQuote(requestId: String, quote: MediaQuote)
  case mediaJob(
    runId: String?, conversationId: String, userMessageId: String,
    assistantMessageId: String, job: MediaJob)
  case conversationsList(conversations: [Conversation])
  case conversation(conversation: Conversation, messages: [Message])
  case searchResults(results: [SearchResult])
  case deleted(id: String)
  case updated(id: String)
  // MCP messages
  case mcpServerAdded(server: MCPServer)
  case mcpServersList(servers: [MCPServer])
  case mcpServerDeleted(serverId: String)
  case mcpServerConnected(status: MCPServerStatus)
  case mcpServerDisconnected(serverId: String)
  case mcpToolsList(tools: [MCPTool])
  case mcpServerUpdated(server: MCPServer)
  // Composio messages
  case composioIntegrations(
    configured: Bool, integrations: [ComposioIntegration], total: Int?, hasMore: Bool?, limit: Int?,
    offset: Int?, error: String?)
  case composioAuthUrl(url: String, toolkit: String, connectionId: String)
  case composioConnections(connections: [ComposioConnection])
  case composioConnected(toolkit: String, connectionId: String, status: String)
  case composioDisconnected(connectionId: String)
  // Quick Actions messages
  case quickActionsList(actions: [QuickAction])
  case quickActionAdded(action: QuickAction)
  case quickActionUpdated(action: QuickAction)
  case quickActionDeleted(actionId: String)
  case actionLearningStarted(actionId: String, actionName: String)
  case actionLearningCompleted(action: QuickAction)
  case workflowsList(workflows: [QuickAction])
  case workflowAdded(workflow: QuickAction)
  case workflowUpdated(workflow: QuickAction)
  case workflowDeleted(actionId: String)
  case slashCommandsList(commands: [CustomSlashCommand])
  case slashCommandAdded(command: CustomSlashCommand)
  case slashCommandUpdated(command: CustomSlashCommand)
  case slashCommandDeleted(commandId: String)
  case imageGenerated(image: String, prompt: String)
  // Memory messages
  case memoriesList(memories: [Memory], total: Int)
  case memoryAdded(memory: Memory)
  case memoryUpdated(success: Bool, id: String)
  case memoryDeleted(success: Bool, id: String)
  case memoriesCleared(success: Bool)
  case activity(status: String, toolName: String?, event: AgentActivityEvent?, runId: String?, conversationId: String?)
  // System automation messages
  case commandApprovalRequest(id: String, runId: String?, conversationId: String?, command: String, description: String, riskLevel: String)
  case secretCommand(id: String, command: String, credentialId: String?, query: String?, origin: String?, usernameRef: String?, passwordRef: String?, runId: String?, conversationId: String?)
  case unknown
}

// MARK: - Data Models

struct Conversation: Codable, Identifiable {
  let id: String
  let title: String?
  let created_at: Int  // Unix timestamp (ms)
  let updated_at: Int  // Unix timestamp (ms)

  var createdDate: Date {
    Date(timeIntervalSince1970: TimeInterval(created_at) / 1000)
  }

  var updatedDate: Date {
    Date(timeIntervalSince1970: TimeInterval(updated_at) / 1000)
  }
}

struct Message: Codable, Identifiable {
  let id: String
  let conversation_id: String
  let role: String  // "user" or "assistant"
  let content: String
  let parts: [MessagePart]?
  let created_at: Int  // Unix timestamp (ms)

  var createdDate: Date {
    Date(timeIntervalSince1970: TimeInterval(created_at) / 1000)
  }

  var isUser: Bool { role == "user" }
  var isAssistant: Bool { role == "assistant" }
}

struct SearchResult: Codable, Identifiable {
  let message_id: String
  let conversation_id: String
  let role: String
  let content: String
  let snippet: String
  let created_at: Int

  var id: String { message_id }
}

// MARK: - Server Message Parsing

struct ServerMessageWrapper: Codable {
  let type: String
  let text: String?
  let conversationId: String?
  let runId: String?
  let messageId: String?
  let error: String?
  let id: String?
  let conversations: [Conversation]?
  let conversation: Conversation?
  let messages: [Message]?
  let results: [SearchResult]?
  // Stats fields
  let isFirst: Bool?
  let timeToFirstChunkMs: Int?
  let tokenCount: Int?
  let durationMs: Int?
  let userMessageId: String?
  let image: String?
  let prompt: String?
  // MCP fields
  let server: MCPServer?
  let servers: [MCPServer]?
  let serverId: String?
  let status: MCPServerStatus?  // For MCP server status
  let tools: [MCPTool]?
  // Composio fields
  let configured: Bool?
  let integrations: [ComposioIntegration]?
  let url: String?
  let toolkit: String?
  let connectionId: String?
  let connections: [ComposioConnection]?
  let total: Int?
  let hasMore: Bool?
  let offset: Int?
  let limit: Int?
  let connectionStatus: String?  // For composio_connected (separate from MCP status)

  // Quick Actions fields
  let actions: [QuickAction]?
  let action: QuickAction?
  let actionId: String?
  let actionName: String?
  let workflows: [QuickAction]?
  let workflow: QuickAction?
  let commands: [CustomSlashCommand]?
  let command: CommandOrString?
  let commandId: String?
  let message: String?
  let agents: [AgentCapability]?
  let defaultAgent: String?
  let models: [MediaModelCapability]?
  let job: MediaJob?
  let assistantMessageId: String?
  let requestId: String?
  let quote: MediaQuote?

  // Memory fields
  let memories: [Memory]?
  let memory: Memory?
  let success: Bool?

  // Activity fields
  let activityStatus: String?
  let toolName: String?
  let event: AgentActivityEvent?

  // Command approval fields
  let riskLevel: String?
  let description: String?
  let secretCommand: String?
  let credentialId: String?
  let usernameRef: String?
  let passwordRef: String?
  let origin: String?
  let query: String?
}

extension ServerMessage {
  static func parse(from data: Data) -> ServerMessage {
    guard let wrapper = try? JSONDecoder().decode(ServerMessageWrapper.self, from: data) else {
      return .unknown
    }

    switch wrapper.type {
    case "chunk":
      return .chunk(
        text: wrapper.text ?? "",
        isFirst: wrapper.isFirst ?? false,
        timeToFirstChunkMs: wrapper.timeToFirstChunkMs
      )

    case "done":
      return .done(
        runId: wrapper.runId,
        conversationId: wrapper.conversationId ?? "",
        messageId: wrapper.messageId,
        userMessageId: wrapper.userMessageId,
        tokenCount: wrapper.tokenCount,
        durationMs: wrapper.durationMs
      )

    case "error":
      return .error(message: wrapper.error ?? "Unknown error", runId: wrapper.runId)

    case "credits_exhausted":
      return .creditsExhausted(message: wrapper.message ?? "Credits exhausted")

    case "pong":
      return .pong

    case "capabilities":
      return .capabilities(agents: wrapper.agents ?? [], defaultAgent: wrapper.defaultAgent)

    case "media_models":
      return .mediaModels(models: wrapper.models ?? [])

    case "media_quote":
      return .mediaQuote(
        requestId: wrapper.requestId ?? "",
        quote: wrapper.quote ?? MediaQuote(kieCredits: nil, detachCredits: nil, summary: nil)
      )

    case "media_job":
      guard let job = wrapper.job else { return .unknown }
      return .mediaJob(
        runId: wrapper.runId,
        conversationId: wrapper.conversationId ?? "",
        userMessageId: wrapper.userMessageId ?? "",
        assistantMessageId: wrapper.assistantMessageId ?? "",
        job: job
      )

    case "conversations_list":
      return .conversationsList(conversations: wrapper.conversations ?? [])

    case "conversation":
      if let conv = wrapper.conversation {
        return .conversation(conversation: conv, messages: wrapper.messages ?? [])
      }
      return .unknown

    case "search_results":
      return .searchResults(results: wrapper.results ?? [])

    case "deleted":
      return .deleted(id: wrapper.id ?? "")

    case "updated":
      return .updated(id: wrapper.id ?? "")

    // MCP messages
    case "mcp_server_added":
      if let server = wrapper.server {
        return .mcpServerAdded(server: server)
      }
      return .unknown

    case "mcp_servers_list":
      return .mcpServersList(servers: wrapper.servers ?? [])

    case "mcp_server_deleted":
      return .mcpServerDeleted(serverId: wrapper.serverId ?? "")

    case "mcp_server_connected":
      if let status = wrapper.status {
        return .mcpServerConnected(status: status)
      }
      return .unknown

    case "mcp_server_disconnected":
      return .mcpServerDisconnected(serverId: wrapper.serverId ?? "")

    case "mcp_tools_list":
      return .mcpToolsList(tools: wrapper.tools ?? [])

    case "mcp_server_updated":
      if let server = wrapper.server {
        return .mcpServerUpdated(server: server)
      }
      return .unknown

    // Composio messages
    case "composio_integrations":
      return .composioIntegrations(
        configured: wrapper.configured ?? false,
        integrations: wrapper.integrations ?? [],
        total: wrapper.total,
        hasMore: wrapper.hasMore,
        limit: wrapper.limit,
        offset: wrapper.offset,
        error: wrapper.error
      )

    case "composio_auth_url":
      return .composioAuthUrl(
        url: wrapper.url ?? "",
        toolkit: wrapper.toolkit ?? "",
        connectionId: wrapper.connectionId ?? ""
      )

    case "composio_connections":
      return .composioConnections(connections: wrapper.connections ?? [])

    case "composio_connected":
      // Status is always ACTIVE when OAuth completes successfully
      return .composioConnected(
        toolkit: wrapper.toolkit ?? "",
        connectionId: wrapper.connectionId ?? "",
        status: "ACTIVE"
      )

    case "composio_disconnected":
      return .composioDisconnected(connectionId: wrapper.connectionId ?? "")

    // Quick Actions messages
    case "quick_actions_list":
      return .quickActionsList(actions: wrapper.actions ?? [])

    case "quick_action_added":
      if let action = wrapper.action {
        return .quickActionAdded(action: action)
      }
      return .unknown

    case "quick_action_updated":
      if let action = wrapper.action {
        return .quickActionUpdated(action: action)
      }
      return .unknown

    case "quick_action_deleted":
      return .quickActionDeleted(actionId: wrapper.actionId ?? "")

    case "action_learning_started":
      return .actionLearningStarted(
        actionId: wrapper.actionId ?? "",
        actionName: wrapper.actionName ?? ""
      )

    case "action_learning_completed":
      if let action = wrapper.action {
        return .actionLearningCompleted(action: action)
      }
      return .unknown

    case "workflows_list":
      return .workflowsList(workflows: wrapper.workflows ?? [])

    case "workflow_added":
      if let workflow = wrapper.workflow {
        return .workflowAdded(workflow: workflow)
      }
      return .unknown

    case "workflow_updated":
      if let workflow = wrapper.workflow {
        return .workflowUpdated(workflow: workflow)
      }
      return .unknown

    case "workflow_deleted":
      return .workflowDeleted(actionId: wrapper.actionId ?? "")

    case "image_generated":
      return .imageGenerated(image: wrapper.image ?? "", prompt: wrapper.prompt ?? "")

    // Slash command messages
    case "slash_commands_list":
      return .slashCommandsList(commands: wrapper.commands ?? [])

    case "slash_command_added":
      if case .command(let cmd) = wrapper.command {
        return .slashCommandAdded(command: cmd)
      }
      return .unknown

    case "slash_command_updated":
      if case .command(let cmd) = wrapper.command {
        return .slashCommandUpdated(command: cmd)
      }
      return .unknown

    case "slash_command_deleted":
      return .slashCommandDeleted(commandId: wrapper.commandId ?? "")

    // Memory messages
    case "memories_list":
      return .memoriesList(memories: wrapper.memories ?? [], total: wrapper.total ?? 0)

    case "memory_added":
      if let memory = wrapper.memory {
        return .memoryAdded(memory: memory)
      }
      return .unknown

    case "memory_updated":
      return .memoryUpdated(success: wrapper.success ?? false, id: wrapper.id ?? "")

    case "memory_deleted":
      return .memoryDeleted(success: wrapper.success ?? false, id: wrapper.id ?? "")

    case "memories_cleared":
      return .memoriesCleared(success: wrapper.success ?? false)

    case "activity":
      return .activity(
        status: wrapper.activityStatus ?? "Processing...", toolName: wrapper.toolName,
        event: wrapper.event, runId: wrapper.runId, conversationId: wrapper.conversationId)

    case "command_approval_request":
      var commandStr = ""
      if case .string(let str) = wrapper.command {
        commandStr = str
      }
      return .commandApprovalRequest(
        id: wrapper.id ?? "",
        runId: wrapper.runId,
        conversationId: wrapper.conversationId,
        command: commandStr,
        description: wrapper.description ?? "",
        riskLevel: wrapper.riskLevel ?? "normal"
      )

    case "secret_command":
      return .secretCommand(
        id: wrapper.id ?? "",
        command: wrapper.secretCommand ?? "",
        credentialId: wrapper.credentialId,
        query: wrapper.query,
        origin: wrapper.origin,
        usernameRef: wrapper.usernameRef,
        passwordRef: wrapper.passwordRef,
        runId: wrapper.runId,
        conversationId: wrapper.conversationId
      )

    default:
      return .unknown
    }
  }
}

/// Structured activity emitted by the Detach runtime. The island uses this rather than
/// trying to infer agent work from display strings.
struct AgentActivityEvent: Codable, Equatable {
  let id: String?
  let agent: String
  let kind: String
  let action: String?
  let phase: String
  let title: String
  let subtitle: String?
  let toolName: String?
  let userFacing: Bool
  let sourceEventType: String?
  let sourceItemType: String?
}

struct AgentActivityUpdate {
  let runId: String?
  let conversationId: String?
  let status: String
  let toolName: String?
  let event: AgentActivityEvent?
}
