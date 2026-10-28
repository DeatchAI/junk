import Foundation

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
  let branchFrom: ConversationBranchFrom?
  /// The folder selected in the floating composer for this agent run.
  let workspacePath: String?
  let integrations: [String]?
  var systemPrompt: String?
  let attachmentContext: String?
  var permissionMode: String?
  let composerMode: ComposerMode?
  let slashCommandId: String?
  let fastMode: Bool?
  let userId: String?  // Supabase user ID for usage billing
  var model: String?  // Optional model override for per-request model selection
  var modelSettings: AgentModelSettings?
  var agent: String?  // Local agent id, e.g. "codex", "claude", or "grok"
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
    branchFrom: ConversationBranchFrom? = nil,
    workspacePath: String? = nil,
    integrations: [String]? = nil, systemPrompt: String? = nil, attachmentContext: String? = nil,
    permissionMode: String? = nil, composerMode: ComposerMode? = nil,
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
    self.branchFrom = branchFrom
    self.workspacePath = workspacePath
    self.integrations = integrations
    self.systemPrompt = systemPrompt
    self.attachmentContext = attachmentContext
    self.permissionMode = permissionMode
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

extension ChatRequest {
  func continuation(in conversationId: String) -> ChatRequest {
    ChatRequest(
      text: "Continue the interrupted task in this conversation from where you left off. Check existing work before repeating actions.",
      displayText: "Continue task", files: files, runId: UUID().uuidString,
      conversationId: conversationId, workspacePath: workspacePath,
      integrations: integrations, systemPrompt: systemPrompt, attachmentContext: attachmentContext,
      permissionMode: permissionMode, composerMode: composerMode,
      slashCommandId: slashCommandId, fastMode: fastMode ?? false, userId: userId,
      model: model, agent: agent, modelSettings: modelSettings,
      zeroDataRetention: zeroDataRetention, actionId: actionId, mcpServerIds: mcpServerIds,
      skills: skills, browserTabs: browserTabs
    )
  }
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

/// A user-selected instruction set from an installed local skill.
/// Only the display metadata and the local SKILL.md path cross the socket; the runtime
/// re-reads and validates the file before it is included in an agent prompt.
struct SkillAttachment: Codable, Identifiable, Equatable, Hashable {
  let id: String
  let name: String
  let path: String
  let summary: String?
}

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
  var details: [String: ActivityJSONValue]? = nil
}

struct AgentActivityUpdate {
  let runId: String?
  let conversationId: String?
  let status: String
  let toolName: String?
  let event: AgentActivityEvent?
}
