import { AgentRegistry } from "../agents/AgentRegistry";
import { SqliteHistory } from "../history/SqliteHistory";
import { NativeHistoryIndex } from "../history/native/NativeHistoryIndex";
import { NativeHistoryService } from "../history/native/NativeHistoryService";
import { send } from "./RuntimeHelpers";
import { SqliteQuickActions } from "../history/SqliteQuickActions";
import { SqliteSlashCommands } from "../history/SqliteSlashCommands";
import { SqliteMCPServers } from "../history/SqliteMCPServers";
import { ComposioSessionManager } from "../composio/ComposioSessionManager";
import { ToolBroker } from "../tools/ToolBroker";
import { BrowserBridge } from "../browser/BrowserBridge";
import { BrowserAutomation } from "../browser/BrowserAutomation";
import { DesktopBridge } from "../desktop/DesktopBridge";
import { SecretBridge } from "../secrets/SecretBridge";
import { CapabilityBroker } from "../capabilities/CapabilityBroker";
import { AgentQuestionBroker } from "../questions/AgentQuestionBroker";
import { GitReviewService } from "../git/GitReviewService";


export const PORT = Number(Bun.env.PORT || 3847);

export function requiredRuntimeToken(): string {
  const token = Bun.env.DETACH_RUNTIME_TOKEN?.trim();
  if (!token) throw new Error("DETACH_RUNTIME_TOKEN is required");
  return token;
}


export const RUNTIME_TOKEN = requiredRuntimeToken();

export const BROWSER_EXTENSION_ORIGIN = "chrome-extension://gdobcabflbojkedmocahijccipghgoij";


export const agents = new AgentRegistry();

export const history = new SqliteHistory();
export const gitReview = new GitReviewService();

export const appClients = new Set<ServerWebSocket>();

let historyNotice: ReturnType<typeof setTimeout> | undefined;
export const nativeHistory = new NativeHistoryService(new NativeHistoryIndex(), history, undefined, () => {
  if (historyNotice) return;
  historyNotice = setTimeout(() => {
    historyNotice = undefined;
    for (const client of appClients) {
      try { send(client, { type: "provider_history_status", ...nativeHistory.status }); } catch {}
    }
  }, 250);
  historyNotice.unref();
});

// Workflows reuse the legacy table without deleting retired Quick Action data.
export const savedWorkflows = new SqliteQuickActions();

export const slashCommands = new SqliteSlashCommands();

export const mcpServers = new SqliteMCPServers();

export const composio = new ComposioSessionManager(mcpServers);

export const tools = new ToolBroker();

export const browserBridge = new BrowserBridge();

export const browserAutomation = new BrowserAutomation(browserBridge);

export const desktopBridge = new DesktopBridge();

export const secretBridge = new SecretBridge();

export const capabilityBroker = new CapabilityBroker(browserAutomation, browserBridge, desktopBridge, secretBridge);

export const activeRuns = new WeakMap<ServerWebSocket, ReturnType<ReturnType<typeof agents.get>["run"]>>();

export const agentQuestions = new AgentQuestionBroker<ServerWebSocket>(send);

export const pendingAgentPermissions = new Map<string, {
  ws: ServerWebSocket;
  resolve: (approved: boolean) => void;
  reject: (error: Error) => void;
  runId: string;
  conversationId: string;
  finishWaiting(): void;
}>();


export type ServerWebSocket = Parameters<NonNullable<Parameters<typeof Bun.serve>[0]["websocket"]>["message"]>[0];
