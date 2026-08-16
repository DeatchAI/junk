import { AgentRegistry } from "./agents/AgentRegistry";
import { selectMCPServers } from "./agents/MCPSelection";
import {
  createLearnedActionSkill,
  learnedActionSkillAttachment,
  type ActionRunTraceEntry,
} from "./actions/ActionSkillManager";
import { BrowserBridge } from "./browser/BrowserBridge";
import { BrowserAutomation, type BrowserActivityUpdate } from "./browser/BrowserAutomation";
import {
  browserTabSystemInstruction,
  normalizeBrowserTabAttachments,
} from "./browser/BrowserTabContext";
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
import {
  demoMediaPath,
  demoMediaURL,
  matchDemoMediaScenario,
  type DemoMediaScenario,
} from "./demo/DemoMediaScenarios";
import { getCapabilities } from "./runtime/CapabilityDetector";
import { isAllowedRuntimeSocketOrigin, isAuthorizedRuntimeRequest } from "./runtime/RuntimeAuth";
import { SqliteHistory } from "./history/SqliteHistory";
import { SqliteMCPServers, statusForServer } from "./history/SqliteMCPServers";
import { SqliteQuickActions } from "./history/SqliteQuickActions";
import { SqliteSlashCommands } from "./history/SqliteSlashCommands";
import { ToolBroker } from "./tools/ToolBroker";
import { CapabilityBroker } from "./capabilities/CapabilityBroker";
import { CAPABILITY_BROKER_ID } from "./capabilities/CapabilityConstants";
import { CAPABILITY_TOOL_NAMES, runCapabilityMCPServer } from "./capabilities/CapabilityMCPServer";
import { resolveSelectedSkillInstructions } from "./skills/SkillResolver";
import { workspaceMemorySystemInstruction } from "./workspace/WorkspaceMemory";
import { HostedModelSessionManager } from "./hosted/HostedModelSessionManager";
import { HostedMediaManager } from "./hosted/HostedMediaManager";
import { normalizeAgentActivity } from "./activity/ActivityNormalizer";
import type {
  ActionDefinition,
  ChatRequest,
  ClientMessage,
  MCPServerConfig,
  MediaGenerateRequest,
  MediaJob,
  Message,
  ServerMessage,
  AgentKind,
} from "./protocol/messages";
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

if (process.argv.includes("--mcp-capability-tools")) {
  await runCapabilityMCPServer();
  process.exit(0);
}

const PORT = Number(Bun.env.PORT || 3847);
function requiredRuntimeToken(): string {
  const token = Bun.env.DETACH_RUNTIME_TOKEN?.trim();
  if (!token) throw new Error("DETACH_RUNTIME_TOKEN is required");
  return token;
}

const RUNTIME_TOKEN = requiredRuntimeToken();
const BROWSER_EXTENSION_ORIGIN = "chrome-extension://gdobcabflbojkedmocahijccipghgoij";

const hostedModels = new HostedModelSessionManager();
const hostedMedia = new HostedMediaManager(hostedModels);
const agents = new AgentRegistry(hostedModels);
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
const capabilityBroker = new CapabilityBroker(browserAutomation, browserBridge, desktopBridge, secretBridge);
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

    if (!isAuthorizedRuntimeRequest(req, url, RUNTIME_TOKEN)) {
      return jsonResponse({ error: "Unauthorized local runtime request" }, 401);
    }

    if (url.pathname === "/api/capabilities") {
      return jsonResponse(await capabilities());
    }

    if (url.pathname === "/api/agent/capabilities" && req.method === "GET") {
      try {
        return jsonResponse({
          ok: true,
          capabilities: await capabilityBroker.list(url.searchParams.get("query") ?? undefined),
        });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/agent/capabilities/describe" && req.method === "POST") {
      try {
        const body = await req.json() as { capabilityId?: string };
        return jsonResponse({ ok: true, result: await capabilityBroker.describe(body.capabilityId ?? "") });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/agent/capabilities/invoke" && req.method === "POST") {
      try {
        const body = await req.json() as {
          capabilityId?: string;
          toolName?: string;
          arguments?: Record<string, unknown>;
          runId?: string;
        };
        return jsonResponse({
          ok: true,
          result: await capabilityBroker.invoke({
            capabilityId: body.capabilityId ?? "",
            toolName: body.toolName ?? "",
            arguments: body.arguments,
            runId: body.runId,
          }),
        });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/browser/status" && req.method === "GET") {
      return jsonResponse(await browserAutomation.getStatus());
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
        const result = await capabilityBroker.executeSecretCommand(body.command ?? "", body.payload ?? {});
        return jsonResponse({ ok: true, result });
      } catch (error) {
        return jsonResponse({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
      }
    }

    if (url.pathname === "/api/sync-profile" && req.method === "POST") {
      const body = await req.json().catch(() => undefined) as { accessToken?: unknown } | undefined;
      const hostedControlPlane = {
        endpoint: Bun.env.DETACH_HOSTED_CONTROL_PLANE_URL,
        accessToken: typeof body?.accessToken === "string" ? body.accessToken : undefined,
      };
      // Hosted model sessions and Composio both use the signed-in profile sync.
      // The Composio project key stays on the hosted control plane; this local
      // runtime receives only the user's bearer token and MCP session details.
      hostedModels.configure(hostedControlPlane);
      composio.configureHostedControlPlane(hostedControlPlane);
      const composioAvailable = await composio.refreshAccess({ force: true });
      return jsonResponse({ success: true, composioAvailable });
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
      if (!isAllowedRuntimeSocketOrigin(url.pathname, origin, BROWSER_EXTENSION_ORIGIN)) {
        return jsonResponse({ error: "Browser bridge origin is not allowed" }, 403);
      }
      if (server.upgrade(req, { data: { kind: "browser-native" } })) {
        return;
      }
    }

    // URLSession does not send an Origin header. Browsers do, so reject any
    // browser-originated attempt to attach as the privileged app socket.
    if (!isAllowedRuntimeSocketOrigin(url.pathname, req.headers.get("origin"), BROWSER_EXTENSION_ORIGIN)) {
      return jsonResponse({ error: "App WebSocket origin is not allowed" }, 403);
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

      case "list_media_models":
        send(ws, { type: "media_models", models: await hostedMedia.models() });
        return;

      case "quote_media":
        send(ws, {
          type: "media_quote",
          requestId: message.requestId,
          quote: await hostedMedia.quote({
            model: message.model,
            prompt: message.prompt || "Media generation quote",
            config: message.config,
            inputs: (message.inputRoles ?? []).map((role) => ({
              uploadId: crypto.randomUUID(),
              role,
            })),
          }),
        });
        return;

      case "generate_media":
        await handleMediaGenerate(ws, message);
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
        send(ws, {
          type: "conversation",
          conversation: entry.conversation,
          messages: await refreshConversationMedia(entry.messages),
        });
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
        await composio.refreshAccess();
        send(ws, {
          type: "mcp_servers_list",
          servers: mcpServers.listWithStatus().filter(
            (server) => server.name !== "Composio MCP" || composio.isAccessAllowed(),
          ),
        });
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
        await composio.disconnect(message.connectionId, message.userId);
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

      default: {
        const unknownMessage = message as { type: string };
        send(ws, { type: "error", error: `Detach runtime does not handle '${unknownMessage.type}' yet.` });
      }
    }
  } catch (error) {
    send(ws, { type: "error", error: error instanceof Error ? error.message : String(error) });
  }
}

async function handleMediaGenerate(
  ws: ServerWebSocket,
  message: MediaGenerateRequest,
) {
  const runId = message.runId ?? crypto.randomUUID();
  const prompt = message.prompt.trim();
  if (!prompt) {
    send(ws, { type: "error", error: "Enter a prompt for the media generation.", runId });
    return;
  }

  const userEntry = history.addUserMessage(message.conversationId, prompt);
  const kind = message.kind === "video" ? "video" : "image";
  const demoScenario = matchDemoMediaScenario(prompt, message.demoMode === true, kind);
  if (demoScenario) {
    await handleDemoMediaGenerate(
      ws,
      message,
      runId,
      prompt,
      demoScenario,
      userEntry.conversation.id,
      userEntry.message.id,
    );
    return;
  }

  let assistantMessage: Message | undefined;
  try {
    const initial = await hostedMedia.create({
      requestKey: message.requestKey,
      model: message.model,
      prompt,
      config: message.config,
      inputs: message.inputs ?? [],
    });
    assistantMessage = history.addMediaMessage(
      userEntry.conversation.id,
      "assistant",
      mediaJobSummary(initial),
      [{ type: "media_job", job: initial }],
    );

    const publish = (job: MediaJob) => publishMediaJob(
      ws,
      runId,
      userEntry.conversation.id,
      userEntry.message.id,
      assistantMessage!.id,
      job,
    );
    const completed = await hostedMedia.waitForCompletion(initial, publish);
    if (completed.state === "succeeded") {
      send(ws, {
        type: "done",
        runId,
        conversationId: userEntry.conversation.id,
        messageId: assistantMessage.id,
        userMessageId: userEntry.message.id,
      });
    } else {
      send(ws, {
        type: "error",
        runId,
        error: completed.error?.message ?? "Media generation could not be completed.",
      });
    }
  } catch (error) {
    const messageText = error instanceof Error ? error.message : String(error);
    if (assistantMessage) {
      history.updateMessageParts(assistantMessage.id, messageText, []);
    } else {
      assistantMessage = history.addAssistantMessage(userEntry.conversation.id, messageText);
    }
    send(ws, { type: "error", error: messageText, runId });
  }
}

async function handleDemoMediaGenerate(
  ws: ServerWebSocket,
  message: MediaGenerateRequest,
  runId: string,
  prompt: string,
  scenario: DemoMediaScenario,
  conversationId: string,
  userMessageId: string,
) {
  const mediaPath = demoMediaPath(scenario.kind, scenario.mediaNumber);
  const mediaFile = Bun.file(mediaPath);
  if (!(await mediaFile.exists())) {
    const errorMessage = `Demo ${scenario.kind} is missing: ${mediaPath}`;
    history.addAssistantMessage(conversationId, errorMessage);
    send(ws, { type: "error", error: errorMessage, runId });
    return;
  }

  const now = new Date().toISOString();
  const jobId = `demo_media_${scenario.id}_${crypto.randomUUID()}`;
  const initial: MediaJob = {
    id: jobId,
    kind: scenario.kind,
    model: `demo-${scenario.kind}`,
    state: "waiting",
    progress: 0,
    prompt,
    config: message.config,
    assets: [],
    createdAt: now,
    updatedAt: now,
  };
  const mimeType = scenario.kind === "image" ? "image/png" : "video/mp4";
  const asset = {
    id: `${jobId}_asset`,
    kind: scenario.kind,
    mimeType,
    url: demoMediaURL(scenario.kind, scenario.mediaNumber),
  };
  const assistantMessage = history.addMediaMessage(
    conversationId,
    "assistant",
    mediaJobSummary(initial),
    [{ type: "media_job", job: initial }],
  );
  const publish = (job: MediaJob) => publishMediaJob(
    ws,
    runId,
    conversationId,
    userMessageId,
    assistantMessage.id,
    job,
  );

  publish(initial);

  let job = initial;
  for (const stage of [
    { delayMs: 1_300, state: "generating", progress: 18 },
    { delayMs: 1_600, state: "generating", progress: 54 },
    { delayMs: 1_300, state: "generating", progress: 82 },
    { delayMs: 900, state: "persisting", progress: 96 },
    { delayMs: 650, state: "succeeded", progress: 100 },
  ] as const) {
    await new Promise<void>((resolve) => setTimeout(resolve, stage.delayMs));
    job = {
      ...job,
      state: stage.state,
      progress: stage.progress,
      assets: stage.state === "succeeded" ? [asset] : [],
      updatedAt: new Date().toISOString(),
    };
    publish(job);
  }

  send(ws, {
    type: "done",
    runId,
    conversationId,
    messageId: assistantMessage.id,
    userMessageId,
  });
}

function publishMediaJob(
  ws: ServerWebSocket,
  runId: string,
  conversationId: string,
  userMessageId: string,
  assistantMessageId: string,
  job: MediaJob,
) {
  history.updateMessageParts(
    assistantMessageId,
    mediaJobSummary(job),
    [{ type: "media_job", job }],
  );
  send(ws, {
    type: "media_job",
    runId,
    conversationId,
    userMessageId,
    assistantMessageId,
    job,
  });
  send(ws, {
    type: "activity",
    runId,
    conversationId,
    activityStatus: mediaActivityStatus(job),
    event: {
      agent: "hosted",
      kind: job.state === "failed" || job.state === "reconciliation_required" ? "error" : "status",
      action: job.kind === "image" ? "image" : "create",
      phase: job.state === "succeeded"
        ? "completed"
        : job.state === "failed" || job.state === "reconciliation_required"
          ? "failed"
          : "updated",
      title: mediaActivityStatus(job),
      subtitle: `${job.progress}% complete`,
      userFacing: true,
    },
  });
}

function mediaActivityStatus(job: MediaJob) {
  if (job.state === "succeeded") return `${job.kind === "image" ? "Image" : "Video"} ready`;
  if (job.state === "failed" || job.state === "reconciliation_required") {
    return `${job.kind === "image" ? "Image" : "Video"} generation failed`;
  }
  if (job.state === "persisting") return "Saving generated media";
  return `Generating ${job.kind} · ${job.progress}%`;
}

function mediaJobSummary(job: MediaJob) {
  if (job.state === "succeeded") {
    if (job.model === "demo-image" || job.model === "demo-video") {
      return `Generated a demo ${job.kind}.`;
    }
    return `Generated ${job.assets.length === 1 ? `a ${job.kind}` : `${job.assets.length} ${job.kind} assets`} with ${job.model}.`;
  }
  if (job.state === "failed" || job.state === "reconciliation_required") {
    return job.error?.message ?? "Media generation could not be completed.";
  }
  if (job.state === "persisting") return "Saving generated media…";
  return `Generating ${job.kind}… ${job.progress}%`;
}

async function refreshConversationMedia(messages: Message[]) {
  return Promise.all(messages.map(async (message) => {
    const mediaPart = message.parts?.find((part) => part.type === "media_job");
    if (!mediaPart || mediaPart.type !== "media_job") return message;
    try {
      const job = await hostedMedia.get(mediaPart.job.id);
      const content = mediaJobSummary(job);
      const parts = [{ type: "media_job" as const, job }];
      history.updateMessageParts(message.id, content, parts);
      return { ...message, content, parts };
    } catch {
      return message;
    }
  }));
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
  const attachedBrowserTabs = normalizeBrowserTabAttachments(message.browserTabs);
  let requestSkills = learnedSkill ? [learnedSkill, ...(message.skills ?? [])] : message.skills;
  const requestedMCPServerIds = attachedBrowserTabs.length > 0
    ? uniqueStrings([...(message.mcpServerIds ?? []), "detach-browser-tools"])
    : message.mcpServerIds;
  const effectiveMCPServerIds = resolveConversationMCPServerIds(
    conversation.conversation.id,
    requestedMCPServerIds,
    Boolean(message.runId)
  );
  await composio.refreshAccess();
  const agentMCPServers = buildAgentMCPServers(effectiveMCPServerIds, runId);
  const capabilityBrokerActive = agentMCPServers.some((server) => server.enabled && server.id === CAPABILITY_BROKER_ID);
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
      action: "prepare",
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
      ], (activity) => sendBrowserActivity(ws, runId, conversation.conversation.id, agent.id, activity));
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

  if (capabilityBrokerActive) {
    capabilityBroker.registerRun(runId, {
      allowedUploadPaths: [
        ...(message.workspacePath ? [message.workspacePath] : []),
        ...(message.files?.map((file) => file.path) ?? []),
      ],
      activitySink: (activity) => sendBrowserActivity(ws, runId, conversation.conversation.id, agent.id, activity),
    });
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
      browserTabSystemInstruction(attachedBrowserTabs),
      message.systemPrompt,
      composerModeSystemInstruction(message.composerMode ?? slashCommand?.mode),
      slashCommand?.promptInstruction,
      actionSkillSystemInstruction(action, learnedSkill),
      resolveSelectedSkillInstructions(requestSkills)
    ),
    mcpServers: agentMCPServers,
    browserTabs: attachedBrowserTabs.length > 0 ? attachedBrowserTabs : undefined,
  };

  const streamCallbacks = {
    onActivity(status, toolName, event) {
      const normalizedEvent = normalizeAgentActivity(agent.id, status, toolName, event);
      if (action) {
        actionTrace.push({ status: normalizedEvent.title, toolName, event: normalizedEvent });
      }
      if (!normalizedEvent.userFacing) return;
      send(ws, {
        type: "activity",
        runId,
        conversationId: conversation.conversation.id,
        activityStatus: normalizedEvent.title,
        toolName,
        event: normalizedEvent,
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
  // UI while deliberately bypassing every installed or Detach Cloud agent.
  const run = demoScenario
    ? createDemoRun(demoScenario, agent.id, streamCallbacks)
    : agent.run(agentRequest, streamCallbacks);

  activeRuns.set(ws, run);

  try {
    const result = await run.finished;
    fullText = fullText || result.text;
    let browserArtifacts;
    if (capabilityBrokerActive) {
      browserArtifacts = await capabilityBroker.endRun(runId);
    }
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
    if (capabilityBrokerActive) await capabilityBroker.endRun(runId).catch(() => undefined);
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
    if (capabilityBrokerActive) await capabilityBroker.endRun(runId).catch(() => undefined);
    if (browserTaskActive) await browserAutomation.endTask(runId).catch(() => undefined);
    activeRuns.delete(ws);
  }
}

async function capabilities(): Promise<ServerMessage> {
  return {
    type: "capabilities",
    agents: await getCapabilities(agents.getCurrentAgent(), hostedModels),
    defaultAgent: agents.getCurrentAgent(),
  };
}

function send(ws: ServerWebSocket, message: ServerMessage) {
  ws.send(JSON.stringify(message));
}

function sendBrowserActivity(
  ws: ServerWebSocket,
  runId: string,
  conversationId: string,
  agentId: AgentKind,
  activity: BrowserActivityUpdate,
) {
  send(ws, {
    type: "activity",
    runId,
    conversationId,
    activityStatus: activity.title,
    toolName: "detach_browser_execute",
    event: {
      id: activity.id,
      agent: agentId,
      kind: activity.action === "error" ? "error" : "mcp_tool",
      action: activity.action,
      phase: activity.phase,
      title: activity.title,
      subtitle: activity.subtitle,
      toolName: "detach_browser_execute",
      userFacing: true,
      sourceEventType: activity.sourceEventType,
      sourceItemType: "browser_primitive",
    },
  });
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
  const persistedServers = mcpServers.listEnabled().filter(
    (server) => server.name !== "Composio MCP" || composio.isAccessAllowed(),
  );
  return selectMCPServers(
    [capabilityMCPServerConfig(runId), browserMCPServerConfig(runId), desktopMCPServerConfig(), secretsMCPServerConfig(), ...persistedServers],
    selectedIds
  );
}

function resolveConversationMCPServerIds(conversationId: string, requestedIds?: string[], modernClient = false) {
  const rememberedIds = history.getMCPServerIds(conversationId);
  const requested = requestedIds ? uniqueStrings(requestedIds) : undefined;

  if (requested && requested.length > 0) {
    const merged = uniqueStrings([CAPABILITY_BROKER_ID, ...rememberedIds, ...requested]);
    history.mergeMCPServerIds(conversationId, merged);
    return merged;
  }

  // Current macOS clients always send runId. When they omit MCP ids, attach only
  // the compact capability broker; operation schemas are loaded by the agent on demand.
  if (!requestedIds && modernClient) {
    return uniqueStrings([CAPABILITY_BROKER_ID, ...rememberedIds]);
  }

  if (!requestedIds && rememberedIds.length > 0) {
    return rememberedIds;
  }

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
      DETACH_RUNTIME_TOKEN: RUNTIME_TOKEN,
      ...(runId ? { DETACH_BROWSER_RUN_ID: runId } : {}),
    },
    approvalPolicy: "auto-approve",
    toolNames: BROWSER_TOOL_NAMES,
    enabled: true,
    created_at: 0,
    updated_at: 0,
  };
}

function capabilityMCPServerConfig(runId?: string): MCPServerConfig {
  const runtime = currentRuntimeCommand();
  return {
    id: CAPABILITY_BROKER_ID,
    name: "Detach capabilities",
    transport: "stdio",
    command: runtime.command,
    args: [...runtime.args, "--mcp-capability-tools"],
    env: {
      DETACH_RUNTIME_URL: `http://127.0.0.1:${PORT}`,
      DETACH_RUNTIME_TOKEN: RUNTIME_TOKEN,
      ...(runId ? { DETACH_CAPABILITY_RUN_ID: runId } : {}),
    },
    approvalPolicy: "auto-approve",
    toolNames: CAPABILITY_TOOL_NAMES,
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
      DETACH_RUNTIME_TOKEN: RUNTIME_TOKEN,
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
    env: {
      DETACH_RUNTIME_URL: `http://127.0.0.1:${PORT}`,
      DETACH_RUNTIME_TOKEN: RUNTIME_TOKEN,
    },
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
