import { activityPart, contentParts, commandTitle, readableText } from "./TranscriptParts";
import { homedir } from "node:os";
import { join } from "node:path";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { ExternalChat, ImportedMessage, ImportSource } from "./ImportTypes";
import { CodexHistoryRPC } from "./ReadOnlyProcess";
import { nativeSourceKey } from "../history/native/NativeIdentity";
import { contentText, existingWorkspace, MAX_DISCOVERY, normalizeMessages, record, sourceKey, text, timestamp, title } from "./Transcript";

export class CodexImportSource implements ImportSource {
  readonly provider = "codex" as const;
  constructor(private readonly connect = async () => {
    const executable = await findExecutable("codex");
    if (!executable) throw new Error("Codex is not installed.");
    return new CodexHistoryRPC(executable);
  }) {}
  async discover() {
    const rpc = await this.connect();
    const chats: ExternalChat[] = [];
    let skipped = 0;
    const namespace = Bun.env.CODEX_HOME || join(homedir(), ".codex");
    try {
      await rpc.initialize();
      for (const archived of [false, true]) {
        let cursor: string | undefined;
        const seen = new Set<string>();
        do {
          const page = await rpc.request("thread/list", { cursor, archived, limit: 100, sortKey: "updated_at",
            sourceKinds: ["cli", "vscode", "exec", "appServer", "unknown"], useStateDbOnly: true });
          if (!Array.isArray(page.data)) throw new Error("Codex returned an unsupported history list.");
          for (const raw of page.data) {
            const thread = record(raw); const id = text(thread.id);
            if (!id) { skipped++; continue; }
            if (thread.ephemeral || thread.parentThreadId) continue;
            const workspacePath = await existingWorkspace(thread.cwd);
            const active = record(thread.status).type === "active";
            chats.push({ provider: this.provider, sourceId: id, sourceKey: nativeSourceKey(this.provider, id), active,
              title: title(thread.name || thread.preview), createdAt: timestamp(thread.createdAt), updatedAt: timestamp(thread.updatedAt),
              workspacePath: text(thread.cwd) || undefined, model: text(thread.model) || undefined,
              canResume: Boolean(workspacePath) && !active && !archived,
              warning: active ? "Running in Codex; finish there before continuing." : archived ? "Archived in Codex; history only."
                : !workspacePath ? "Original project folder is unavailable; history only." : undefined });
          }
          cursor = text(page.nextCursor) || undefined;
          if (cursor && seen.has(cursor)) throw new Error("Codex returned a repeated history cursor.");
          if (cursor) seen.add(cursor);
          if (seen.size > 100) throw new Error("Codex history has too many empty or unsupported pages.");
        } while (cursor && chats.length < MAX_DISCOVERY);
        if (chats.length >= MAX_DISCOVERY) break;
      }
      return { chats: chats.slice(0, MAX_DISCOVERY), complete: chats.length < MAX_DISCOVERY && skipped === 0,
        notices: chats.length >= MAX_DISCOVERY ? [`Codex: history discovery reached its ${MAX_DISCOVERY} session safety limit.`] : [] };
    } finally { rpc.close(); }
  }
  async read(chat: ExternalChat) {
    const rpc = await this.connect();
    try {
      await rpc.initialize();
      const result: ImportedMessage[] = [];
      let cursor: string | undefined;
      const seen = new Set<string>();
      let previousTurnId: string | undefined;
      const appendTurn = (turn: any) => {
        for (const item of turn.items ?? []) {
          const message = codexMessage(item, timestamp(turn.startedAt, chat.createdAt));
          if (!message) continue;
          if (message.role === "user" && typeof turn.id === "string") {
            message.branchPoint = { kind: "codex", beforeTurnId: turn.id, previousTurnId };
          }
          result.push(message);
        }
        previousTurnId = typeof turn.id === "string" ? turn.id : undefined;
      };
      try {
        do {
          const page = await rpc.request("thread/turns/list", { threadId: chat.sourceId, cursor, limit: 100, sortDirection: "asc", itemsView: "full" });
          for (const turn of page.data ?? []) appendTurn(turn);
          cursor = text(page.nextCursor) || undefined;
          if (cursor && seen.has(cursor)) throw new Error("Codex returned a repeated transcript cursor.");
          if (cursor) seen.add(cursor);
          if (seen.size > 100 || result.length > 10_000) throw new Error("Conversation is too large to import.");
        } while (cursor);
      } catch (error) {
        if (!/unknown.method|not.support|legacy|paginated/i.test(String(error))) throw error;
        result.length = 0;
        previousTurnId = undefined;
        const legacy = await rpc.request("thread/read", { threadId: chat.sourceId, includeTurns: true });
        for (const turn of legacy.thread?.turns ?? []) appendTurn(turn);
      }
      return normalizeMessages(result);
    } finally { rpc.close(); }
  }
}

export function codexMessage(raw: unknown, createdAt: number): ImportedMessage | undefined {
  const item = record(raw);
  const role = item.type === "userMessage" ? "user" : "assistant";
  let parts = item.type === "userMessage" ? contentParts(item.content) : [];
  const status = item.status === "failed" || item.status === "declined" ? "failed" : "completed";
  const id = text(item.id) || undefined;
  if (item.type === "agentMessage" || item.type === "plan") parts = [{ type: "text", text: text(item.text) }];
  if (item.type === "commandExecution") parts = [activityPart("command", commandTitle(text(item.command)), {
    id, status, command: text(item.command), output: text(item.aggregatedOutput),
  })];
  if (item.type === "fileChange") parts = [activityPart("file_change", "Updated files", {
    id, status, text: JSON.stringify(item.changes ?? [], null, 2),
  })];
  if (item.type === "mcpToolCall" || item.type === "dynamicToolCall") parts = [activityPart("tool", "Used tool", {
    id, status, toolName: text(item.tool), text: JSON.stringify(item.arguments ?? {}, null, 2),
    output: contentText(record(item.result).content) || text(item.error),
  })];
  if (item.type === "webSearch") parts = [activityPart("search", "Searched the web", {
    id, text: text(item.query) || JSON.stringify(item.action ?? {}, null, 2),
  })];
  const content = readableText(parts);
  return content.trim() || parts.some((part) => part.type === "activity") ? { role, content, parts, createdAt } : undefined;
}
