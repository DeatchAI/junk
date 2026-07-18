export type ClientMessage =
  | ChatRequest
  | { type: "ping" }
  | { type: "stop_stream" }
  | { type: "capabilities" }
  | { type: "list_conversations"; limit?: number; offset?: number }
  | { type: "get_conversation"; conversationId: string }
  | { type: "delete_conversation"; conversationId: string }
  | { type: "delete_message"; messageId: string }
  | { type: "edit_message"; messageId: string; content: string }
  | { type: "search"; query: string; limit?: number }
  | { type: "update_ai_settings"; agent?: AgentKind; model?: string }
  | { type: "update_browser_settings" }
  | { type: "list_quick_actions" }
  | ({ type: "add_quick_action" } & ActionDefinitionCreateFields)
  | {
      type: "update_quick_action";
      actionId: string;
      name?: string;
      prompt?: string;
      integrations?: string[];
      systemImage?: string;
      shortcut?: string;
      enabled?: boolean;
      position?: number;
      mcpServerIds?: string[];
      skills?: SkillAttachment[];
      inputPolicy?: ActionInputPolicy;
      executionMode?: ActionExecutionMode;
    }
  | { type: "list_workflows" }
  | ({ type: "add_workflow" } & ActionDefinitionCreateFields)
  | {
      type: "update_workflow";
      actionId: string;
      name?: string;
      prompt?: string;
      systemImage?: string;
      shortcut?: string;
      enabled?: boolean;
      position?: number;
      mcpServerIds?: string[];
      skills?: SkillAttachment[];
      inputPolicy?: ActionInputPolicy;
      executionMode?: ActionExecutionMode;
    }
  | { type: "delete_workflow"; actionId: string }
  | { type: "delete_quick_action"; actionId: string }
  | { type: "list_mcp_servers" }
  | {
      type: "add_mcp_server";
      name: string;
      transport: "stdio" | "sse" | "http";
      command?: string;
      args?: string[];
      url?: string;
      headers?: Record<string, string>;
      env?: Record<string, string>;
      enabled?: boolean;
    }
  | { type: "update_mcp_server"; serverId: string; name?: string; transport?: "stdio" | "sse" | "http"; command?: string; args?: string[]; url?: string; headers?: Record<string, string>; env?: Record<string, string>; enabled?: boolean }
  | { type: "delete_mcp_server"; serverId: string }
  | { type: "connect_mcp_server"; serverId: string }
  | { type: "disconnect_mcp_server"; serverId: string }
  | { type: "list_mcp_tools" }
  | { type: "list_composio_integrations"; limit?: number; offset?: number; query?: string; userId?: string }
  | { type: "connect_composio_account"; toolkit: string; userId?: string; callbackUrl?: string }
  | { type: "list_composio_connections"; userId?: string }
  | { type: "disconnect_composio_account"; connectionId: string; userId?: string }
  | { type: "list_memories"; limit?: number; offset?: number }
  | { type: "add_memory"; content: string; category?: string; importance?: number }
  | { type: "update_memory"; id: string; content: string; category?: string }
  | { type: "delete_memory"; id: string }
  | { type: "clear_memories" }
  | { type: "desktop_command_result"; id: string; ok: boolean; result?: unknown; error?: string }
  | { type: "secret_command_result"; id: string; ok: boolean; resultJson?: string; error?: string }
  | { type: "command_approval_response"; requestId: string; approved: boolean }
  | { type: "list_slash_commands" }
  | {
      type: "add_slash_command";
      command: string;
      title: string;
      subtitle?: string;
      systemImage?: string;
      replacementText?: string;
      promptInstruction?: string;
      mode?: ComposerMode;
    }
  | {
      type: "update_slash_command";
      commandId: string;
      command?: string;
      title?: string;
      subtitle?: string;
      systemImage?: string;
      replacementText?: string;
      promptInstruction?: string;
      mode?: ComposerMode;
      enabled?: boolean;
      position?: number;
    }
  | { type: "delete_slash_command"; commandId: string };

export type AgentKind = "codex" | "claude" | "grok";

export type ComposerMode = "explain_only" | "plan_only" | "review_only" | "debug_only";

export interface SlashCommandDefinition {
  id: string;
  command: string;
  title: string;
  subtitle?: string;
  systemImage?: string;
  replacementText?: string;
  promptInstruction?: string;
  mode?: ComposerMode;
  enabled: boolean;
  position: number;
  isCustom: boolean;
}

export interface ChatRequest {
  type: "chat";
  /** Stable client-generated identity for a detached agent run. */
  runId?: string;
  /** Debug builds set this flag so exact demo prompts can bypass real agents. */
  demoMode?: boolean;
  text: string;
  displayText?: string;
  files?: FileAttachmentRequest[];
  conversationId?: string;
  contextMessages?: ConversationContextMessage[];
  systemPrompt?: string;
  composerMode?: ComposerMode;
  slashCommandId?: string;
  fastMode?: boolean;
  model?: string;
  agent?: AgentKind;
  workspacePath?: string;
  actionId?: string;
  /** Omitted values allow conversation-remembered MCPs or legacy auto-discovery; an explicit empty list means no MCPs. */
  mcpServerIds?: string[];
  mcpServers?: MCPServerConfig[];
  skills?: SkillAttachment[];
}

export interface FileAttachmentRequest {
  path: string;
  mimeType?: string;
}

export interface SkillAttachment {
  id: string;
  name: string;
  path: string;
  summary?: string;
}

export type ActionKind = "quick_action" | "workflow";
export type ActionTrigger = "selection_menu" | "manual" | "hotkey";
export type ActionInputPolicy = "requires_selection" | "optional_selection" | "none";
export type ActionExecutionMode = "open_composer" | "run_immediately";

export interface ActionDefinitionCreateFields {
  name: string;
  prompt: string;
  integrations?: string[];
  systemImage?: string;
  shortcut?: string;
  mcpServerIds?: string[];
  skills?: SkillAttachment[];
  inputPolicy?: ActionInputPolicy;
  executionMode?: ActionExecutionMode;
}

export interface Conversation {
  id: string;
  title?: string;
  created_at: number;
  updated_at: number;
}

export interface Message {
  id: string;
  conversation_id: string;
  role: "user" | "assistant";
  content: string;
  created_at: number;
}

export interface ConversationContextMessage {
  role: "user" | "assistant";
  content: string;
}

export type ServerMessage =
  | { type: "pong" }
  | { type: "capabilities"; agents: AgentCapability[]; defaultAgent: AgentKind }
  | {
      type: "activity";
      runId?: string;
      conversationId?: string;
      activityStatus: string;
      toolName?: string;
      event?: AgentActivityEvent;
    }
  | { type: "chunk"; text: string; isFirst?: boolean; timeToFirstChunkMs?: number }
  | {
      type: "done";
      runId?: string;
      conversationId: string;
      messageId?: string;
      userMessageId?: string;
      tokenCount?: number;
      durationMs?: number;
    }
  | { type: "error"; error: string; runId?: string }
  | { type: "conversations_list"; conversations: Conversation[] }
  | { type: "conversation"; conversation: Conversation; messages: Message[] }
  | { type: "search_results"; results: SearchResult[] }
  | { type: "deleted"; id: string }
  | { type: "updated"; id: string }
  | { type: "quick_actions_list"; actions: ActionDefinition[] }
  | { type: "quick_action_added"; action: ActionDefinition }
  | { type: "quick_action_updated"; action: ActionDefinition }
  | { type: "quick_action_deleted"; actionId: string }
  | { type: "action_learning_started"; actionId: string; actionName: string }
  | { type: "action_learning_completed"; action: ActionDefinition }
  | { type: "workflows_list"; workflows: ActionDefinition[] }
  | { type: "workflow_added"; workflow: ActionDefinition }
  | { type: "workflow_updated"; workflow: ActionDefinition }
  | { type: "workflow_deleted"; actionId: string }
  | { type: "slash_commands_list"; commands: SlashCommandDefinition[] }
  | { type: "slash_command_added"; command: SlashCommandDefinition }
  | { type: "slash_command_updated"; command: SlashCommandDefinition }
  | { type: "slash_command_deleted"; commandId: string }
  | { type: "mcp_server_added"; server: MCPServerConfig; status?: MCPServerStatus }
  | { type: "mcp_servers_list"; servers: Array<MCPServerConfig & { status?: MCPServerStatus }> }
  | { type: "mcp_server_deleted"; serverId: string }
  | { type: "mcp_server_connected"; status: MCPServerStatus }
  | { type: "mcp_server_disconnected"; serverId: string }
  | { type: "mcp_server_updated"; server: MCPServerConfig }
  | { type: "mcp_tools_list"; tools: MCPTool[] }
  | {
      type: "composio_integrations";
      configured: boolean;
      integrations: ComposioIntegration[];
      total?: number;
      hasMore?: boolean;
      offset?: number;
      limit?: number;
      error?: string;
    }
  | { type: "composio_auth_url"; url: string; toolkit: string; connectionId: string }
  | { type: "composio_connections"; connections: ComposioConnection[] }
  | { type: "composio_connected"; toolkit: string; connectionId: string; connectionStatus: string }
  | { type: "composio_disconnected"; connectionId: string }
  | { type: "memories_list"; memories: unknown[]; total: number }
  | { type: "memory_added"; memory: unknown }
  | { type: "memory_updated"; success: boolean; id: string }
  | { type: "memory_deleted"; success: boolean; id: string }
  | { type: "memories_cleared"; success: boolean }
  | {
      type: "command_approval_request";
      id: string;
      runId?: string;
      conversationId?: string;
      command: string;
      description: string;
      riskLevel: "safe" | "normal" | "dangerous";
    };

export interface AgentCapability {
  id: AgentKind;
  displayName: string;
  installed: boolean;
  executablePath?: string;
  authHint?: string;
  models: AgentModelCapability[];
  defaultModel?: string;
}

export interface AgentModelCapability {
  id: string;
  displayName: string;
}

export type AgentActivityKind =
  | "lifecycle"
  | "attachment"
  | "command"
  | "file_change"
  | "mcp_tool"
  | "plan"
  | "error"
  | "status";

export type AgentActivityPhase =
  | "started"
  | "updated"
  | "completed"
  | "failed";

export interface AgentActivityEvent {
  id?: string;
  agent: AgentKind;
  kind: AgentActivityKind;
  phase: AgentActivityPhase;
  title: string;
  subtitle?: string;
  toolName?: string;
  userFacing: boolean;
  sourceEventType?: string;
  sourceItemType?: string;
  details?: Record<string, unknown>;
}

export interface SearchResult {
  message_id: string;
  conversation_id: string;
  role: string;
  content: string;
  snippet: string;
  created_at: number;
}

export interface ActionDefinition {
  id: string;
  name: string;
  prompt: string;
  kind: ActionKind;
  trigger: ActionTrigger;
  inputPolicy: ActionInputPolicy;
  executionMode: ActionExecutionMode;
  integrations?: string[];
  mcpServerIds?: string[];
  skills?: SkillAttachment[];
  learnedSkillPath?: string;
  learnedSkillVersion?: number;
  learningStatus?: "none" | "learning" | "ready" | "stale" | "failed";
  lastSuccessfulRunAt?: number;
  systemImage?: string;
  shortcut?: string;
  enabled: boolean;
  position: number;
  created_at: number;
  updated_at: number;
}

export type QuickAction = ActionDefinition;

export interface MCPServerConfig {
  id: string;
  name: string;
  transport: "stdio" | "sse" | "http";
  command?: string;
  args?: string[];
  url?: string;
  headers?: Record<string, string>;
  env?: Record<string, string>;
  approvalPolicy?: "prompt" | "auto-approve";
  toolNames?: string[];
  enabled: boolean;
  created_at: number;
  updated_at: number;
}

export interface MCPServerStatus {
  id: string;
  name: string;
  connected: boolean;
  tools?: MCPTool[];
  error?: string;
}

export interface MCPTool {
  name: string;
  description?: string;
}

export interface ComposioIntegration {
  id: string;
  name: string;
  description: string;
  icon: string;
  connected: boolean;
  connectionId?: string;
}

export interface ComposioConnection {
  id: string;
  toolkit: string;
  status: string;
  connectedAt: string;
}
