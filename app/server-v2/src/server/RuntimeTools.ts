import { type MCPServerConfig } from "../protocol/messages";
import { mcpServers, composio, history, nativeHistory, PORT, RUNTIME_TOKEN } from "./RuntimeContext";
import { selectMCPServers } from "../agents/MCPSelection";
import { uniqueStrings } from "./RuntimeHelpers";
import { CAPABILITY_BROKER_ID } from "../capabilities/CapabilityConstants";
import { BROWSER_TOOL_NAMES } from "../browser/BrowserMCPServer";
import { CAPABILITY_TOOL_NAMES } from "../capabilities/CapabilityMCPServer";
import { MACOS_TOOL_NAMES } from "../desktop/DesktopMCPServer";
import { SECRETS_TOOL_NAMES } from "../secrets/SecretsMCPServer";


export function buildAgentMCPServers(selectedIds?: string[], runId?: string): MCPServerConfig[] {
  const persistedServers = mcpServers.listEnabled().filter(
    (server) => server.name !== "Composio MCP" || composio.isAccessAllowed(),
  );
  return selectMCPServers(
    [capabilityMCPServerConfig(runId), browserMCPServerConfig(runId), desktopMCPServerConfig(runId), secretsMCPServerConfig(), ...persistedServers],
    selectedIds
  );
}


export function resolveConversationMCPServerIds(conversationId: string, requestedIds?: string[], modernClient = false) {
  const native = /^(native_|pending_|demo_)/.test(conversationId);
  const rememberedIds = native ? nativeHistory.index.mcpIDs(conversationId) : history.getMCPServerIds(conversationId);
  const requested = requestedIds ? uniqueStrings(requestedIds) : undefined;

  if (requested && requested.length > 0) {
    const merged = uniqueStrings([CAPABILITY_BROKER_ID, ...rememberedIds, ...requested]);
    if (native) nativeHistory.index.rememberMCPs(conversationId, merged);
    else history.mergeMCPServerIds(conversationId, merged);
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


export function browserMCPServerConfig(runId?: string): MCPServerConfig {
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


export function capabilityMCPServerConfig(runId?: string): MCPServerConfig {
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


export function desktopMCPServerConfig(runId?: string): MCPServerConfig {
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
      ...(runId ? { DETACH_DESKTOP_RUN_ID: runId } : {}),
    },
    approvalPolicy: "auto-approve",
    toolNames: MACOS_TOOL_NAMES,
    enabled: true,
    created_at: 0,
    updated_at: 0,
  };
}


export function secretsMCPServerConfig(): MCPServerConfig {
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


export function currentRuntimeCommand() {
  const execPath = process.execPath;
  const main = Bun.main;

  if (execPath.endsWith("/bun") || execPath.endsWith("/bun-debug")) {
    return { command: execPath, args: [main] };
  }

  return { command: execPath, args: [] };
}
