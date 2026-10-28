import Foundation
import Combine

// MARK: - Client → Server Messages

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
  let refreshLoaded: Bool?

  init(limit: Int? = 50, offset: Int? = 0, refreshLoaded: Bool? = nil) {
    self.limit = limit
    self.offset = offset
    self.refreshLoaded = refreshLoaded
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
  let temperature: Double?
  let maxSteps: Int?
  let systemPrompt: String?
  let zeroDataRetention: Bool?
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
