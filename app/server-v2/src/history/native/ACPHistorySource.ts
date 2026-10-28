import { toolPart } from "../../imports/TranscriptParts";
import { findExecutable } from "../../runtime/CapabilityDetector";
import { ReadOnlyHistoryRPC } from "../../imports/ReadOnlyProcess";
import { contentText, existingWorkspace, MAX_DISCOVERY, normalizeMessages, record, text, timestamp, title } from "../../imports/Transcript";
import type { ExternalChat, ImportedMessage, ImportSource } from "../../imports/ImportTypes";
import { nativeSourceKey } from "./NativeIdentity";

export class ACPHistorySource implements ImportSource {
  constructor(readonly provider: "fx" | "grok" | "omp", private readonly find = () => findExecutable(provider)) {}
  private async connect() {
    const executable = await this.find();
    if (!executable) throw new Error("Provider CLI is not installed.");
    return new ReadOnlyHistoryRPC(executable, "acp", this.provider === "grok" ? ["agent", "--no-leader", "stdio"] : ["acp"]);
  }
  async discover() {
    const rpc = await this.connect();
    try {
      const caps = record(await rpc.initialize());
      if (!record(record(caps.agentCapabilities).sessionCapabilities).list) throw new Error("This provider version does not expose session listing.");
      const loadable = record(caps.agentCapabilities).loadSession === true;
      const chats: ExternalChat[] = []; const cursors = new Set<string>(); let cursor: string | undefined; let skipped = 0;
      do {
        const page = await rpc.request("session/list", { cursor });
        if (!Array.isArray(page.sessions)) throw new Error("Provider returned an unsupported session list.");
        for (const raw of page.sessions) {
          const row = record(raw); const id = text(row.sessionId); if (!id) { skipped++; continue; }
          const workspace = text(row.cwd); const available = await existingWorkspace(workspace);
          const active = record(row._meta).active === true || row.status === "active";
          chats.push({ provider: this.provider, sourceId: id, sourceKey: nativeSourceKey(this.provider, id),
            title: title(row.title), createdAt: timestamp(row.createdAt ?? row.updatedAt), updatedAt: timestamp(row.updatedAt),
            workspacePath: workspace || undefined, active, canResume: loadable && Boolean(available) && !active,
            warning: active ? "Running in another client; live takeover is not supported." : !available ? "Project folder is unavailable."
              : !loadable ? "This provider cannot load saved sessions through ACP." : undefined });
        }
        cursor = text(page.nextCursor) || undefined;
        if (cursor && cursors.has(cursor)) throw new Error("Provider returned a repeated session cursor.");
        if (cursor) cursors.add(cursor);
        if (cursors.size > 100) throw new Error("Session listing exceeded its safe page limit.");
      } while (cursor && chats.length < MAX_DISCOVERY);
      return { chats: chats.slice(0, MAX_DISCOVERY), complete: !cursor && chats.length < MAX_DISCOVERY && skipped === 0,
        notices: chats.length >= MAX_DISCOVERY ? [`${this.provider}: history discovery reached its ${MAX_DISCOVERY} session safety limit.`] : [] };
    } finally { rpc.close(); }
  }
  async read(chat: ExternalChat) {
    if (!chat.workspacePath) throw new Error("The original workspace is unavailable.");
    const rpc = await this.connect(); const messages: ImportedMessage[] = [];
    const tools = new Map<string, { message: ImportedMessage; title: string; body: string }>(); let chunkKind = "";
    try {
      const caps = await rpc.initialize();
      if (record(caps.agentCapabilities).loadSession !== true) throw new Error("Saved-session loading is unsupported.");
      rpc.onSessionUpdate = (params) => {
        if (params?.sessionId !== chat.sourceId) return;
        const update = record(params.update); const kind = update.sessionUpdate;
        if (kind === "user_message_chunk" || kind === "agent_message_chunk") {
          const content = contentText([update.content]);
          const role = kind === "user_message_chunk" ? "user" : "assistant";
          if (content && chunkKind === kind && messages.at(-1)?.role === role) messages[messages.length - 1]!.content += content;
          else if (content) messages.push({ role, content, createdAt: chat.createdAt });
          chunkKind = kind;
        } else if (kind === "tool_call" || kind === "tool_call_update") {
          chunkKind = "";
          const id = text(update.toolCallId); if (!id) return;
          let tool = tools.get(id);
          if (!tool) {
            tool = { message: { role: "assistant", content: "", createdAt: chat.createdAt }, title: "Tool", body: "" };
            tools.set(id, tool); messages.push(tool.message);
          }
          tool.title = text(update.title) || tool.title;
          if (Array.isArray(update.content)) tool.body = update.content.map((part: any) =>
            part.type === "content" ? contentText([part.content]) : "").filter(Boolean).join("\n");
          tool.message.parts = [{ ...(tool.message.parts?.[0] ?? toolPart(tool.title, update.rawInput)), id,
            output: tool.body, status: update.status === "failed" ? "failed" : "completed",
          }];
        }
      };
      await rpc.request("session/load", { sessionId: chat.sourceId, cwd: chat.workspacePath, mcpServers: [] });
      return normalizeMessages(messages);
    } finally { rpc.close(); }
  }
}
