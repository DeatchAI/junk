import { AgentRegistry } from "./agents/AgentRegistry";
import { selectMCPServers } from "./agents/MCPSelection";
import {
  createLearnedActionSkill,
  learnedActionSkillAttachment,
  type ActionRunTraceEntry,
} from "./actions/ActionSkillManager";
import { BrowserBridge } from "./browser/BrowserBridge";
import { BrowserAutomation, type BrowserAutomationSettings } from "./browser/BrowserAutomation";
import { BROWSER_TOOL_NAMES, runBrowserMCPServer } from "./browser/BrowserMCPServer";
import {
  learnBrowserSkillFromArtifacts,
  learnedBrowserSkillAttachments,
} from "./browser/BrowserSkillManager";
import { runNativeBrowserHost } from "./browser/NativeBrowserHost";
import { SecretBridge } from "./secrets/SecretBridge";
import { SECRETS_TOOL_NAMES, runSecretsMCPServer } from "./secrets/SecretsMCPServer";
import { ComposioSessionManager } from "./composio/ComposioSessionManager";
import { composerModeSystemInstruction } from "./composer/composerModes";
import { DesktopBridge } from "./desktop/DesktopBridge";
import { MACOS_TOOL_NAMES, runDesktopMCPServer } from "./desktop/DesktopMCPServer";
import { createDemoRun, matchDemoScenario } from "./demo/DemoScenarios";
import { getCapabilities } from "./runtime/CapabilityDetector";
import { SqliteHistory } from "./history/SqliteHistory";
import { SqliteMCPServers, statusForServer } from "./history/SqliteMCPServers";
import { SqliteQuickActions } from "./history/SqliteQuickActions";
import { SqliteSlashCommands } from "./history/SqliteSlashCommands";
import { ToolBroker } from "./tools/ToolBroker";
import { resolveSelectedSkillInstructions } from "./skills/SkillResolver";
import { workspaceMemorySystemInstruction } from "./workspace/WorkspaceMemory";
import type { ActionDefinition, ChatRequest, ClientMessage, MCPServerConfig, Message, ServerMessage } from "./protocol/messages";
import type { AgentPermissionRequest } from "./agents/AgentAdapter";

if (process.argv.includes("--native-browser-host")) {
  await runNativeBrowserHost();
  process.exit(0);
}

if (process.argv.includes("--mcp-browser-tools")) {
  await runBrowserMCPServer();
  process.exit(0);
}

if (process.argv.includes("--mcp-macos-tools")) {
  await runDesktopMCPServer();
  process.exit(0);
}

if (process.argv.includes("--mcp-secrets-tools")) {
  await runSecretsMCPServer();
  process.exit(0);
}

const PORT = Number(Bun.env.PORT || 3847);
const BROWSER_EXTENSION_ORIGIN = "chrome-extension://gdobcabflbojkedmocahijccipghgoij";

const agents = new AgentRegistry();
const history = new SqliteHistory();
const quickActions = new SqliteQuickActions();
const slashCommands = new SqliteSlashCommands();
const mcpServers = new SqliteMCPServers();
const composio = new ComposioSessionManager(mcpServers);
const tools = new ToolBroker();
const browserBridge = new BrowserBridge();
const browserAutomation = new BrowserAutomation(browserBridge);
const desktopBridge = new DesktopBridge();
const secretBridge = new SecretBridge();
const activeRuns = new WeakMap<ServerWebSocket, ReturnType<ReturnType<typeof agents.get>["run"]>>();
const pendingAgentPermissions = new Map<string, {
  ws: ServerWebSocket;
  resolve: (approved: boolean) => void;
  timeout: Timer;
}>();

type ServerWebSocket = Parameters<NonNullable<Parameters<typeof Bun.serve>[0]["websocket"]>["message"]>[0];

const server = Bun.serve<{ kind: "app" | "browser-native" }>({
  port: PORT,
  hostname: "127.0.0.1",
  async fetch(req, server) {
    const url = new URL(req.url);

    if (url.pathname === "/api/capabilities") {
      return jsonResponse(await capabilities());
    }

    if (url.pathname === "/api/browser/status" && req.method === "GET") {
      return jsonResponse(await browserAutomation.getStatus());
    }

    if (url.pathname === "/api/browser/settings" && req.method === "GET") {
      return jsonResponse({ ok: true, settings: browserAutomation.getSettings() });
    }

    if (url.pathname === "/api/browser/settings" && req.method === "POST") {
      try {
        const body = await req.json() as Partial<BrowserAutomationSettings>;
        return jsonResponse({ ok: true, settings: browserAutomation.updateSettings(body) });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/browser/artifacts" && req.method === "GET") {
      const runId = url.searchParams.get("runId")?.trim();
      if (!runId) return jsonResponse({ ok: false, error: "runId is required" }, 400);
      return jsonResponse({ ok: true, ...browserAutomation.getArtifacts(runId) });
    }

    if (url.pathname === "/api/browser/command" && req.method === "POST") {
      try {
        const body = await req.json() as { command?: string; payload?: Record<string, unknown>; runId?: string };
        const result = await browserAutomation.execute({
          command: body.command ?? "",
          payload: body.payload ?? {},
        }, body.runId);
        return jsonResponse({ ok: true, result });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/desktop/status" && req.method === "GET") {
      return jsonResponse(desktopBridge.getStatus());
    }

    if (url.pathname === "/api/desktop/command" && req.method === "POST") {
      try {
        const body = await req.json() as { command?: string; payload?: Record<string, unknown> };
        const result = await desktopBridge.execute({
          command: body.command ?? "",
          payload: body.payload ?? {},
        });
        return jsonResponse({ ok: true, result });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/secrets/command" && req.method === "POST") {
      try {
        const body = await req.json() as { command?: "search" | "use"; payload?: Record<string, unknown> };
        const payload = body.payload ?? {};
        if (body.command === "search") {
          const resultJson = await secretBridge.execute({ command: "secrets.search", payload });
          return jsonResponse({ ok: true, result: JSON.parse(resultJson) });
        }
        if (body.command === "use") {
          const prepared = await browserBridge.execute({ command: "browser.prepare_secret_fill", payload });
          const resultJson = await secretBridge.execute({ command: "secrets.use_browser", payload: { ...payload, prepared } });
          const authorized = JSON.parse(resultJson) as { approved?: boolean; username?: string; password?: string };
          const username = authorized.username;
          const password = authorized.password;
          authorized.username = undefined;
          authorized.password = undefined;
          if (authorized.approved !== true || typeof username !== "string" || typeof password !== "string") {
            throw new Error("Touch ID completed without a valid credential payload.");
          }
          const filled = await browserBridge.execute({
            command: "browser.secure_fill",
            payload: { ...payload, username, password },
          }) as {
            filled?: boolean;
            submitted?: boolean;
            inspection?: string;
            navigation?: { changed?: boolean; documentReloaded?: boolean; beforeUrl?: string; afterUrl?: string; title?: string; status?: string };
            next?: string;
          };
          if (!filled.filled) throw new Error("Chrome did not confirm the secure credential fill.");
          return jsonResponse({
            ok: true,
            result: {
              filled: true,
              submitted: filled.submitted === true,
              inspection: filled.inspection || "locked_until_navigation",
              navigation: filled.navigation,
              next: filled.next || (filled.submitted ? "wait_for_navigation" : "submit_required"),
            },
          });
        }
        return jsonResponse({ ok: false, error: "Unknown secure credential command" }, 400);
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/sync-profile" && req.method === "POST") {
      return jsonResponse({ success: true });
    }

    if (url.pathname === "/api/usage" && req.method === "GET") {
      const nextReset = new Date();
      nextReset.setMonth(nextReset.getMonth() + 1);

      return jsonResponse({
        creditsUsed: 0,
        creditLimit: 1_000_000,
        isUnlimited: true,
        planType: "local",
        nextResetDate: nextReset.toISOString(),
        hasBYOKAccess: false,
        requiresBYOK: false,
        hasAllModels: true,
        allowedModels: ["Codex", "Claude", "Grok"],
      });
    }

    if (url.pathname === "/api/browser/native") {
      const origin = req.headers.get("origin");
      if (origin && origin !== BROWSER_EXTENSION_ORIGIN) {
        return jsonResponse({ error: "Browser bridge origin is not allowed" }, 403);
      }
      if (server.upgrade(req, { data: { kind: "browser-native" } })) {
        return;
      }
    }

    if (server.upgrade(req, { data: { kind: "app" } })) {
      return;
    }

    return jsonResponse({
      name: "Detach Runtime",
      version: "0.1.0",
      port: PORT,
    });
  },
  websocket: {
    open(ws) {
      if (isBrowserNativeSocket(ws)) {
        browserBridge.attachNativeSocket(ws);
        return;
      }
      desktopBridge.attachAppSocket(ws);
      secretBridge.attachAppSocket(ws);
      log("client connected");
    },
    close(ws) {
      if (browserBridge.isNativeSocket(ws)) {
        browserBridge.detachNativeSocket(ws);
        return;
      }
      desktopBridge.detachAppSocket(ws);
      secretBridge.detachAppSocket(ws);
      activeRuns.get(ws)?.cancel();
      activeRuns.delete(ws);
      resolvePermissionsForSocket(ws, false);
      log("client disconnected");
    },
    async message(ws, raw) {
      if (browserBridge.isNativeSocket(ws)) {
        browserBridge.handleNativeMessage(raw.toString());
        return;
      }
      await handleMessage(ws, raw.toString());
    },
  },
});

log(`Detach runtime listening on ${PORT}`);

async function handleMessage(ws: ServerWebSocket, raw: string) {
  let message: ClientMessage;

  try {
    message = JSON.parse(raw);
  } catch {
    send(ws, { type: "error", error: "Invalid message format" });
    return;
  }

  try {
    switch (message.type) {
      case "ping":
        send(ws, { type: "pong" });
        return;

      case "capabilities":
        send(ws, await capabilities());
        return;

      case "chat":
        await handleChat(ws, message);
        return;

      case "stop_stream":
        activeRuns.get(ws)?.cancel();
        activeRuns.delete(ws);
        resolvePermissionsForSocket(ws, false);
        send(ws, { type: "activity", activityStatus: "Stopped" });
        return;

      case "command_approval_response":
        resolveAgentPermission(message.requestId, message.approved);
        return;

      case "desktop_command_result":
        desktopBridge.handleResult(message);
        return;

      case "secret_command_result":
        secretBridge.handleResult(message);
        return;

      case "update_ai_settings":
        if (message.agent && agents.has(message.agent)) {
          agents.setCurrentAgent(message.agent);
        }
        return;

      case "list_conversations":
        send(ws, { type: "conversations_list", conversations: history.list(message.limit, message.offset) });
        return;

      case "get_conversation": {
        const entry = history.get(message.conversationId);
        if (!entry) {
          send(ws, { type: "error", error: "Conversation not found" });
          return;
        }
        send(ws, { type: "conversation", conversation: entry.conversation, messages: entry.messages });
        return;
      }

      case "delete_conversation":
        history.deleteConversation(message.conversationId);
        send(ws, { type: "deleted", id: message.conversationId });
        return;

      case "delete_message":
        history.deleteMessage(message.messageId);
        send(ws, { type: "deleted", id: message.messageId });
        return;

      case "edit_message":
        history.editMessage(message.messageId, message.content);
        send(ws, { type: "updated", id: message.messageId });
        return;

      case "search":
        send(ws, { type: "search_results", results: history.search(message.query, message.limit) });
        return;

      case "list_quick_actions":
        send(ws, { type: "quick_actions_list", actions: quickActions.list("quick_action") });
        return;

      case "add_quick_action": {
        const action = quickActions.add({
          ...message,
          kind: "quick_action",
          trigger: "selection_menu",
          inputPolicy: message.inputPolicy ?? "optional_selection",
          executionMode: message.executionMode ?? "run_immediately",
        });
        send(ws, { type: "quick_action_added", action });
        return;
      }

      case "update_quick_action": {
        const action = quickActions.update(message.actionId, {
          name: message.name,
          prompt: message.prompt,
          integrations: message.integrations,
          systemImage: message.systemImage,
          shortcut: message.shortcut,
          enabled: message.enabled,
          position: message.position,
          mcpServerIds: message.mcpServerIds,
          skills: message.skills,
          inputPolicy: message.inputPolicy,
          executionMode: message.executionMode,
        });
        if (!action) {
          send(ws, { type: "error", error: "Quick action not found" });
          return;
        }
        send(ws, { type: "quick_action_updated", action });
        return;
      }

      case "delete_quick_action":
        quickActions.delete(message.actionId);
        send(ws, { type: "quick_action_deleted", actionId: message.actionId });
        return;

      case "list_workflows":
        send(ws, { type: "workflows_list", workflows: quickActions.list("workflow") });
        return;

      case "add_workflow": {
        const workflow = quickActions.add({
          ...message,
          kind: "workflow",
          trigger: "manual",
          inputPolicy: message.inputPolicy ?? "none",
          executionMode: message.executionMode ?? "run_immediately",
        });
        send(ws, { type: "workflow_added", workflow });
        return;
      }

      case "update_workflow": {
        const workflow = quickActions.update(message.actionId, {
          name: message.name,
          prompt: message.prompt,
          systemImage: message.systemImage,
          shortcut: message.shortcut,
          enabled: message.enabled,
          position: message.position,
          mcpServerIds: message.mcpServerIds,
          skills: message.skills,
          inputPolicy: message.inputPolicy,
          executionMode: message.executionMode,
        });
        if (!workflow) {
          send(ws, { type: "error", error: "Workflow not found" });
          return;
        }
        send(ws, { type: "workflow_updated", workflow });
        return;
      }

      case "delete_workflow":
        quickActions.delete(message.actionId);
        send(ws, { type: "workflow_deleted", actionId: message.actionId });
        return;

      case "list_slash_commands":
        send(ws, { type: "slash_commands_list", commands: slashCommands.list() });
        return;

      case "add_slash_command": {
        const command = slashCommands.add({
          command: message.command,
          title: message.title,
          subtitle: message.subtitle,
          systemImage: message.systemImage,
          replacementText: message.replacementText,
          promptInstruction: message.promptInstruction,
          mode: message.mode,
        });
        send(ws, { type: "slash_command_added", command });
        return;
      }

      case "update_slash_command": {
        const command = slashCommands.update(message.commandId, {
          command: message.command,
          title: message.title,
          subtitle: message.subtitle,
          systemImage: message.systemImage,
          replacementText: message.replacementText,
          promptInstruction: message.promptInstruction,
          mode: message.mode,
          enabled: message.enabled,
          position: message.position,
        });
        if (!command) {
          send(ws, { type: "error", error: "Slash command not found" });
          return;
        }
        send(ws, { type: "slash_command_updated", command });
        return;
      }

      case "delete_slash_command":
        slashCommands.delete(message.commandId);
        send(ws, { type: "slash_command_deleted", commandId: message.commandId });
        return;

      case "list_mcp_servers":
        send(ws, { type: "mcp_servers_list", servers: mcpServers.listWithStatus() });
        return;

      case "add_mcp_server": {
        const server = mcpServers.add({
          name: message.name,
          transport: message.transport,
          command: message.command,
          args: message.args,
          url: message.url,
          headers: message.headers,
          env: message.env,
          enabled: message.enabled ?? true,
        });
        send(ws, { type: "mcp_server_added", server, status: statusForServer(server) });
        return;
      }

      case "update_mcp_server": {
        const server = mcpServers.update(message.serverId, {
          name: message.name,
          transport: message.transport,
          command: message.command,
          args: message.args,
          url: message.url,
          headers: message.headers,
          env: message.env,
          enabled: message.enabled,
        });
        if (!server) {
          send(ws, { type: "error", error: "MCP server not found" });
          return;
        }
        send(ws, { type: "mcp_server_updated", server });
        return;
      }

      case "delete_mcp_server":
        if (!mcpServers.delete(message.serverId)) {
          send(ws, { type: "error", error: "MCP server not found" });
          return;
        }
        send(ws, { type: "mcp_server_deleted", serverId: message.serverId });
        return;

      case "connect_mcp_server": {
        const server = mcpServers.update(message.serverId, { enabled: true });
        if (!server) {
          send(ws, { type: "error", error: "MCP server not found" });
          return;
        }
        send(ws, { type: "mcp_server_connected", status: statusForServer(server) });
        return;
      }

      case "disconnect_mcp_server": {
        const server = mcpServers.update(message.serverId, { enabled: false });
        if (!server) {
          send(ws, { type: "error", error: "MCP server not found" });
          return;
        }
        send(ws, { type: "mcp_server_disconnected", serverId: message.serverId });
        return;
      }

      case "list_mcp_tools":
        send(ws, {
          type: "mcp_tools_list",
          tools: [
            ...tools.summary().tools.map((name) => ({ name })),
            ...mcpServers.listEnabled().map((server) => ({
              name: server.name,
              description: `${server.transport.toUpperCase()} MCP server`,
            })),
          ],
        });
        return;

      case "list_composio_integrations":
        send(ws, await composio.listIntegrations({
          limit: message.limit,
          offset: message.offset,
          query: message.query,
          userId: message.userId,
        }));
        return;

      case "connect_composio_account": {
        const result = await composio.connectToolkit({
          toolkit: message.toolkit,
          userId: message.userId,
          callbackUrl: message.callbackUrl,
        });
        for (const response of result.messages) send(ws, response);
        if (result.pending) {
          result.pending
            .then((responses) => {
              for (const response of responses) send(ws, response);
            })
            .catch((error) => {
              send(ws, {
                type: "error",
                error: error instanceof Error ? error.message : String(error),
              });
            });
        }
        return;
      }

      case "list_composio_connections":
        send(ws, { type: "composio_connections", connections: await composio.listConnections({ userId: message.userId }) });
        return;

      case "disconnect_composio_account":
        await composio.disconnect(message.connectionId);
        send(ws, { type: "composio_disconnected", connectionId: message.connectionId });
        return;

      case "list_memories":
        send(ws, { type: "memories_list", memories: [], total: 0 });
        return;

      case "add_memory":
        send(ws, { type: "memory_added", memory: { id: `memory_${Date.now()}`, content: message.content } });
        return;

      case "update_memory":
        send(ws, { type: "memory_updated", success: true, id: message.id });
        return;

      case "delete_memory":
        send(ws, { type: "memory_deleted", success: true, id: message.id });
        return;

      case "clear_memories":
        send(ws, { type: "memories_cleared", success: true });
        return;

      case "update_browser_settings":
        browserAutomation.updateSettings({
          mode: message.mode,
          cdpUrl: message.cdpUrl ?? "",
          headless: message.headless,
          viewportWidth: message.viewportWidth,
          viewportHeight: message.viewportHeight,
          userDataDir: message.userDataDir ?? "",
        });
        return;

      default: {
        const unknownMessage = message as { type: string };
        send(ws, { type: "error", error: `Detach runtime does not handle '${unknownMessage.type}' yet.` });
      }
    }
  } catch (error) {
    send(ws, { type: "error", error: error instanceof Error ? error.message : String(error) });
  }
}

async function handleChat(ws: ServerWebSocket, message: ChatRequest) {
  const startTime = Date.now();
  const runId = message.runId ?? crypto.randomUUID();
  const priorMessages = message.conversationId ? history.get(message.conversationId)?.messages ?? [] : [];
  const storedUserText = message.displayText?.trim() || message.text || "";
  const conversation = history.addUserMessage(message.conversationId, storedUserText);
  const agent = agents.get(message.agent);
  const demoScenario = matchDemoScenario(storedUserText, message.demoMode === true);
  const action = message.actionId ? quickActions.get(message.actionId) : undefined;
  const slashCommand = message.slashCommandId ? slashCommands.get(message.slashCommandId) : undefined;
  const learnedSkill = action ? learnedActionSkillAttachment(action) : undefined;
  let requestSkills = learnedSkill ? [learnedSkill, ...(message.skills ?? [])] : message.skills;
  const effectiveMCPServerIds = resolveConversationMCPServerIds(
    conversation.conversation.id,
    message.mcpServerIds,
    Boolean(message.runId)
  );
  const agentMCPServers = buildAgentMCPServers(effectiveMCPServerIds, runId);
  let fullText = "";
  let firstChunkAt: number | undefined;
  const actionTrace: ActionRunTraceEntry[] = [];

  send(ws, {
    type: "activity",
    runId,
    conversationId: conversation.conversation.id,
    activityStatus: `Using ${agent.displayName}`,
    event: {
      agent: agent.id,
      kind: "lifecycle",
      phase: "started",
      title: `${agent.displayName} is working`,
      subtitle: "Preparing your task",
      userFacing: true,
    },
  });

  let browserTaskActive = effectiveMCPServerIds?.includes("detach-browser-tools") ?? false;
  if (browserTaskActive) {
    try {
      await browserAutomation.beginTask(runId, [
        ...(message.workspacePath ? [message.workspacePath] : []),
        ...(message.files?.map((file) => file.path) ?? []),
      ]);
      const browserContext = await browserAutomation.getTaskContext(runId).catch(() => undefined);
      requestSkills = uniqueSkillAttachments([
        ...(requestSkills ?? []),
        ...learnedBrowserSkillAttachments(storedUserText, browserContext?.url),
      ]);
    } catch (error) {
      await browserAutomation.endTask(runId, false).catch(() => undefined);
      browserTaskActive = false;
      const errorMessage = error instanceof Error ? error.message : String(error);
      const assistantText = agentFailureSummary(agent.displayName, errorMessage, fullText);
      const assistantMessage = history.addAssistantMessage(conversation.conversation.id, assistantText);
      send(ws, { type: "error", error: errorMessage, runId });
      send(ws, {
        type: "done",
        runId,
        conversationId: conversation.conversation.id,
        messageId: assistantMessage.id,
        userMessageId: conversation.message.id,
        tokenCount: estimateTokenCount(assistantText),
        durationMs: Date.now() - startTime,
      });
      return;
    }
  }

  const agentRequest: ChatRequest = {
    ...message,
    runId,
    skills: requestSkills,
    mcpServerIds: effectiveMCPServerIds,
    conversationId: conversation.conversation.id,
    contextMessages: buildContextMessages(priorMessages),
    systemPrompt: mergeSystemInstructions(
      workspaceMemorySystemInstruction(),
      message.systemPrompt,
      composerModeSystemInstruction(message.composerMode ?? slashCommand?.mode),
      slashCommand?.promptInstruction,
      actionSkillSystemInstruction(action, learnedSkill),
      resolveSelectedSkillInstructions(requestSkills)
    ),
    mcpServers: agentMCPServers,
  };

  const streamCallbacks = {
    onActivity(status, toolName, event) {
      if (action) {
        actionTrace.push({ status, toolName, event });
      }
      send(ws, {
        type: "activity",
        runId,
        conversationId: conversation.conversation.id,
        activityStatus: status,
        toolName,
        event,
      });
    },
    onChunk(text) {
      if (!firstChunkAt) {
        firstChunkAt = Date.now();
        send(ws, {
          type: "chunk",
          text,
          isFirst: true,
          timeToFirstChunkMs: firstChunkAt - startTime,
        });
      } else {
        send(ws, { type: "chunk", text });
      }
      fullText += text;
    },
    onPermission(request) {
      return requestAgentPermission(ws, request, runId, conversation.conversation.id);
    },
  } satisfies Parameters<typeof agent.run>[1];

  // Exact demo prompts from Debug app builds exercise the real streaming/activity
  // UI while deliberately bypassing every installed or hosted AI agent.
  const run = demoScenario
    ? createDemoRun(demoScenario, agent.id, streamCallbacks)
    : agent.run(agentRequest, streamCallbacks);

  activeRuns.set(ws, run);

  try {
    const result = await run.finished;
    fullText = fullText || result.text;
    let browserArtifacts;
    if (browserTaskActive) {
      await browserAutomation.endTask(runId);
      browserTaskActive = false;
      browserArtifacts = browserAutomation.getArtifacts(runId);
    }
    const assistantMessage = history.addAssistantMessage(conversation.conversation.id, fullText);
    const learnedAction = maybeLearnActionSkill(ws, action, Boolean(learnedSkill), actionTrace, fullText);
    const learnedBrowser = browserArtifacts ? learnBrowserSkillFromArtifacts(browserArtifacts) : undefined;
    if (learnedBrowser) {
      send(ws, {
        type: "activity",
        runId,
        conversationId: conversation.conversation.id,
        activityStatus: `Learned ${learnedBrowser.hostname} for faster future browser tasks`,
        toolName: "Browser learning",
      });
    }
    send(ws, {
      type: "done",
      runId,
      conversationId: conversation.conversation.id,
      messageId: assistantMessage.id,
      userMessageId: conversation.message.id,
      tokenCount: estimateTokenCount(fullText),
      durationMs: Date.now() - startTime,
    });
    if (learnedAction) {
      if (learnedAction.learningStatus === "ready") {
        send(ws, { type: "action_learning_completed", action: learnedAction });
      } else {
        sendActionUpdated(ws, learnedAction);
      }
    }
  } catch (error) {
    if (browserTaskActive) {
      await browserAutomation.endTask(runId).catch(() => undefined);
      browserTaskActive = false;
    }
    const errorMessage = error instanceof Error ? error.message : String(error);
    const assistantText = agentFailureSummary(agent.displayName, errorMessage, fullText);
    const assistantMessage = history.addAssistantMessage(conversation.conversation.id, assistantText);
    send(ws, { type: "error", error: errorMessage, runId });
    send(ws, {
      type: "done",
      runId,
      conversationId: conversation.conversation.id,
      messageId: assistantMessage.id,
      userMessageId: conversation.message.id,
      tokenCount: estimateTokenCount(assistantText),
      durationMs: Date.now() - startTime,
    });
  } finally {
    if (browserTaskActive) await browserAutomation.endTask(runId).catch(() => undefined);
    activeRuns.delete(ws);
  }
}

async function capabilities(): Promise<ServerMessage> {
  return {
    type: "capabilities",
    agents: await getCapabilities(agents.getCurrentAgent()),
    defaultAgent: agents.getCurrentAgent(),
  };
}

function send(ws: ServerWebSocket, message: ServerMessage) {
  ws.send(JSON.stringify(message));
}

function requestAgentPermission(
  ws: ServerWebSocket,
  request: AgentPermissionRequest,
  runId: string,
  conversationId: string
) {
  const id = `approval_${crypto.randomUUID()}`;

  return new Promise<boolean>((resolve) => {
    const timeout = setTimeout(() => resolveAgentPermission(id, false), 60_000);
    pendingAgentPermissions.set(id, { ws, resolve, timeout });
    send(ws, {
      type: "command_approval_request",
      id,
      runId,
      conversationId,
      command: request.toolName || request.title,
      description: request.description,
      riskLevel: request.riskLevel,
    });
  });
}

function resolveAgentPermission(id: string, approved: boolean) {
  const pending = pendingAgentPermissions.get(id);
  if (!pending) return;
  clearTimeout(pending.timeout);
  pendingAgentPermissions.delete(id);
  pending.resolve(approved);
}

function resolvePermissionsForSocket(ws: ServerWebSocket, approved: boolean) {
  for (const [id, pending] of pendingAgentPermissions) {
    if (pending.ws === ws) resolveAgentPermission(id, approved);
  }
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function buildAgentMCPServers(selectedIds?: string[], runId?: string): MCPServerConfig[] {
  return selectMCPServers(
    [browserMCPServerConfig(runId), desktopMCPServerConfig(), secretsMCPServerConfig(), ...mcpServers.listEnabled()],
    selectedIds
  );
}

function resolveConversationMCPServerIds(conversationId: string, requestedIds?: string[], modernClient = false) {
  const rememberedIds = history.getMCPServerIds(conversationId);
  const requested = requestedIds ? uniqueStrings(requestedIds) : undefined;

  if (requested && requested.length > 0) {
    const merged = uniqueStrings([...rememberedIds, ...requested]);
    history.mergeMCPServerIds(conversationId, merged);
    return merged;
  }

  if (!requestedIds && rememberedIds.length > 0) {
    return rememberedIds;
  }

  // Current macOS clients always send runId. When they omit MCP ids on a new
  // conversation, that means no attachment—not the pre-v2 "load everything"
  // fallback retained for clients without runId.
  if (!requestedIds && modernClient) return [];

  return requestedIds;
}

function mergeSystemInstructions(...instructions: Array<string | undefined>) {
  const defined = instructions.map((instruction) => instruction?.trim()).filter((instruction): instruction is string => Boolean(instruction));
  return defined.length > 0 ? defined.join("\n\n") : undefined;
}

function uniqueStrings(values: string[]) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function uniqueSkillAttachments<T extends { path?: string; id?: string }>(skills: T[]) {
  const seen = new Set<string>();
  return skills.filter((skill) => {
    const key = skill.path?.trim() || skill.id?.trim();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function actionSkillSystemInstruction(action?: ActionDefinition, learnedSkill?: { path: string }) {
  if (!action) return undefined;
  if (learnedSkill) {
    return [
      `This request is running Detach action "${action.name}".`,
      "A learned action skill is attached. Follow it first and avoid rediscovering the workflow unless a learned step fails.",
    ].join("\n");
  }
  return [
    `This request is running Detach action "${action.name}".`,
    "This action has not been learned yet. Complete it normally; Detach will learn the successful procedure afterward for faster future runs.",
  ].join("\n");
}

function maybeLearnActionSkill(
  ws: ServerWebSocket,
  action: ActionDefinition | undefined,
  hasUsableLearnedSkill: boolean,
  trace: ActionRunTraceEntry[],
  assistantText: string
) {
  if (!action || hasUsableLearnedSkill) {
    if (action) {
      quickActions.update(action.id, { lastSuccessfulRunAt: Date.now() });
    }
    return undefined;
  }

  send(ws, {
    type: "activity",
    activityStatus: "Learning this action for faster future runs",
    toolName: "Action learning",
  });
  send(ws, { type: "action_learning_started", actionId: action.id, actionName: action.name });

  try {
    const learned = createLearnedActionSkill(action, trace, assistantText);
    return quickActions.update(action.id, {
      learnedSkillPath: learned.path,
      learnedSkillVersion: learned.version,
      learningStatus: "ready",
      lastSuccessfulRunAt: Date.now(),
    });
  } catch (error) {
    const failed = quickActions.update(action.id, {
      learningStatus: "failed",
      lastSuccessfulRunAt: Date.now(),
    });
    send(ws, {
      type: "activity",
      activityStatus: `Could not learn action: ${error instanceof Error ? error.message : String(error)}`,
      toolName: "Action learning",
    });
    return failed;
  }
}

function sendActionUpdated(ws: ServerWebSocket, action: ActionDefinition) {
  if (action.kind === "workflow") {
    send(ws, { type: "workflow_updated", workflow: action });
  } else {
    send(ws, { type: "quick_action_updated", action });
  }
}

function browserMCPServerConfig(runId?: string): MCPServerConfig {
  const runtime = currentRuntimeCommand();
  return {
    id: "detach-browser-tools",
    name: "Detach Browser",
    transport: "stdio",
    command: runtime.command,
    args: [...runtime.args, "--mcp-browser-tools"],
    env: {
      DETACH_RUNTIME_URL: `http://127.0.0.1:${PORT}`,
      ...(runId ? { DETACH_BROWSER_RUN_ID: runId } : {}),
    },
    approvalPolicy: "auto-approve",
    toolNames: BROWSER_TOOL_NAMES,
    enabled: true,
    created_at: 0,
    updated_at: 0,
  };
}

function desktopMCPServerConfig(): MCPServerConfig {
  const runtime = currentRuntimeCommand();
  return {
    id: "detach-macos-tools",
    name: "Detach macOS",
    transport: "stdio",
    command: runtime.command,
    args: [...runtime.args, "--mcp-macos-tools"],
    env: {
      DETACH_RUNTIME_URL: `http://127.0.0.1:${PORT}`,
    },
    approvalPolicy: "auto-approve",
    toolNames: MACOS_TOOL_NAMES,
    enabled: true,
    created_at: 0,
    updated_at: 0,
  };
}

function secretsMCPServerConfig(): MCPServerConfig {
  const runtime = currentRuntimeCommand();
  return {
    id: "detach-secrets-tools",
    name: "Detach Secrets",
    transport: "stdio",
    command: runtime.command,
    args: [...runtime.args, "--mcp-secrets-tools"],
    env: { DETACH_RUNTIME_URL: `http://127.0.0.1:${PORT}` },
    approvalPolicy: "auto-approve",
    toolNames: SECRETS_TOOL_NAMES,
    enabled: true,
    created_at: 0,
    updated_at: 0,
  };
}

function currentRuntimeCommand() {
  const execPath = process.execPath;
  const main = Bun.main;

  if (execPath.endsWith("/bun") || execPath.endsWith("/bun-debug")) {
    return { command: execPath, args: [main] };
  }

  return { command: execPath, args: [] };
}

function isBrowserNativeSocket(ws: ServerWebSocket) {
  return ((ws as unknown as { data?: { kind?: string } }).data?.kind) === "browser-native";
}

function estimateTokenCount(text: string) {
  return Math.max(0, Math.ceil(text.length / 4));
}

function agentFailureSummary(agentName: string, errorMessage: string, partialText: string) {
  const trimmedPartial = partialText.trim();
  const failure = `${agentName} stopped before completing this turn: ${errorMessage}`;
  return trimmedPartial ? `${trimmedPartial}\n\n${failure}` : failure;
}

function buildContextMessages(messages: Message[]) {
  const maxMessages = Number(Bun.env.DETACH_CONTEXT_MESSAGES || 24);
  const maxChars = Number(Bun.env.DETACH_CONTEXT_CHARS || 48_000);
  const selected: { role: "user" | "assistant"; content: string }[] = [];
  let totalChars = 0;

  for (const message of [...messages].reverse()) {
    const content = message.content.trim();
    if (!content) continue;

    if (selected.length >= maxMessages) break;
    if (totalChars + content.length > maxChars && selected.length > 0) break;

    selected.push({ role: message.role, content: truncateMiddle(content, maxChars) });
    totalChars += content.length;
  }

  return selected.reverse();
}

function truncateMiddle(text: string, maxChars: number) {
  if (text.length <= maxChars) return text;
  const head = text.slice(0, Math.floor(maxChars * 0.65));
  const tail = text.slice(text.length - Math.floor(maxChars * 0.25));
  return `${head}\n\n[...conversation context truncated...]\n\n${tail}`;
}

function log(message: string) {
  if (Bun.env.NODE_ENV !== "test") {
    console.log(`[detach-runtime] ${message}`);
  }
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

let isShuttingDown = false;

function shutdown(signal: string) {
  if (isShuttingDown) return;
  isShuttingDown = true;
  log(`shutting down (${signal})`);
  void (async () => {
    await browserAutomation.stop();
    await server.stop(true);
    process.exit(0);
  })();
}
