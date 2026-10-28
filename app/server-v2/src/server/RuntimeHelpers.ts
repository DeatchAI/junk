import { type ServerMessage, type AgentKind, type Message } from "../protocol/messages";
import { getCapabilities } from "../runtime/CapabilityDetector";
import { agents, type ServerWebSocket } from "./RuntimeContext";
import { type BrowserActivityUpdate } from "../browser/BrowserAutomation";


export async function capabilities(): Promise<ServerMessage> {
  return {
    type: "capabilities",
    agents: await getCapabilities(agents.getCurrentAgent()),
    defaultAgent: agents.getCurrentAgent(),
  };
}


export function send(ws: ServerWebSocket, message: ServerMessage) {
  ws.send(JSON.stringify(message));
}


export function sendBrowserActivity(
  ws: ServerWebSocket,
  runId: string,
  conversationId: string | undefined,
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


export function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}


export function mergeSystemInstructions(...instructions: Array<string | undefined>) {
  const defined = instructions.map((instruction) => instruction?.trim()).filter((instruction): instruction is string => Boolean(instruction));
  return defined.length > 0 ? defined.join("\n\n") : undefined;
}


export function uniqueStrings(values: string[]) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}


export function uniqueSkillAttachments<T extends { path?: string; id?: string }>(skills: T[]) {
  const seen = new Set<string>();
  return skills.filter((skill) => {
    const key = skill.path?.trim() || skill.id?.trim();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}


export function isBrowserNativeSocket(ws: ServerWebSocket) {
  return ((ws as unknown as { data?: { kind?: string } }).data?.kind) === "browser-native";
}


export function estimateTokenCount(text: string) {
  return Math.max(0, Math.ceil(text.length / 4));
}


export function agentFailureSummary(agentName: string, errorMessage: string, partialText: string) {
  const trimmedPartial = partialText.trim();
  const failure = `${agentName} stopped before completing this turn: ${errorMessage}`;
  return trimmedPartial ? `${trimmedPartial}\n\n${failure}` : failure;
}


export function buildContextMessages(messages: Message[]) {
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


export function truncateMiddle(text: string, maxChars: number) {
  if (text.length <= maxChars) return text;
  const head = text.slice(0, Math.floor(maxChars * 0.65));
  const tail = text.slice(text.length - Math.floor(maxChars * 0.25));
  return `${head}\n\n[...conversation context truncated...]\n\n${tail}`;
}


export function log(message: string) {
  if (Bun.env.NODE_ENV !== "test") {
    console.log(`[detach-runtime] ${message}`);
  }
}
