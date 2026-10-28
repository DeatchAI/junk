import Foundation

enum ServerMessage {
  case contextSummary(ChatContextSummary)
  case commandApprovalResolved(id: String, outcome: String)
  case chunk(text: String, isFirst: Bool, timeToFirstChunkMs: Int?)
  case done(
    runId: String?, conversationId: String, messageId: String?, userMessageId: String?, tokenCount: Int?,
    durationMs: Int?)
  case error(message: String, runId: String?)
  case pong
  case capabilities(agents: [AgentCapability], defaultAgent: String?)
  case conversationsList(conversations: [Conversation], offset: Int, hasMore: Bool)
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
  case actionLearningStarted(actionId: String, actionName: String)
  case actionLearningCompleted(action: SavedWorkflow)
  case workflowsList(workflows: [SavedWorkflow])
  case workflowAdded(workflow: SavedWorkflow)
  case workflowUpdated(workflow: SavedWorkflow)
  case workflowDeleted(actionId: String)
  case slashCommandsList(commands: [CustomSlashCommand])
  case slashCommandAdded(command: CustomSlashCommand)
  case slashCommandUpdated(command: CustomSlashCommand)
  case slashCommandDeleted(commandId: String)
  case activity(status: String, toolName: String?, event: AgentActivityEvent?, runId: String?, conversationId: String?)
  case commandApprovalRequest(id: String, runId: String?, conversationId: String?, command: String, description: String, riskLevel: String)
  case secretCommand(id: String, command: String, credentialId: String?, query: String?, origin: String?, usernameRef: String?, passwordRef: String?, runId: String?, conversationId: String?)
  case unknown
}

// MARK: - Data Models

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
  let outcome: String?
  let contextSummary: ChatContextSummary?
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

  // Workflow fields
  let action: SavedWorkflow?
  let actionId: String?
  let actionName: String?
  let workflows: [SavedWorkflow]?
  let workflow: SavedWorkflow?
  let commands: [CustomSlashCommand]?
  let command: CommandOrString?
  let commandId: String?
  let message: String?
  let agents: [AgentCapability]?
  let defaultAgent: String?
  let assistantMessageId: String?
  let requestId: String?

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

    case "pong":
      return .pong

    case "capabilities":
      return .capabilities(agents: wrapper.agents ?? [], defaultAgent: wrapper.defaultAgent)

    case "conversations_list":
      return .conversationsList(conversations: wrapper.conversations ?? [], offset: wrapper.offset ?? 0, hasMore: wrapper.hasMore ?? false)

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

    case "activity":
      return .activity(
        status: wrapper.activityStatus ?? "Processing...", toolName: wrapper.toolName,
        event: wrapper.event, runId: wrapper.runId, conversationId: wrapper.conversationId)

    case "context_summary":
      return wrapper.contextSummary.map(ServerMessage.contextSummary) ?? .unknown

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

    case "command_approval_resolved":
      return .commandApprovalResolved(id: wrapper.id ?? "", outcome: wrapper.outcome ?? "cancelled")

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
