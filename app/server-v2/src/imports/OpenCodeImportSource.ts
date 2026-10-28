import { contentParts, readableText, toolPart } from "./TranscriptParts";
import type { MessagePart } from "../protocol/messages";
import { homedir } from "node:os";
import { join } from "node:path";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { ExternalChat, ImportedMessage, ImportSource } from "./ImportTypes";
import { readHistoryCommand, supportsACPSessionLoad } from "./ReadOnlyProcess";
import { nativeSourceKey } from "../history/native/NativeIdentity";
import { existingWorkspace, MAX_DISCOVERY, normalizeMessages, record, sourceKey, text, timestamp, title } from "./Transcript";

export class OpenCodeImportSource implements ImportSource {
  readonly provider = "opencode" as const;
  constructor(private readonly find = () => findExecutable("opencode"), private readonly readCommand = readHistoryCommand,
    private readonly supportsResume = supportsACPSessionLoad) {}
  async discover() {
    const executable = await this.find();
    if (!executable) throw new Error("OpenCode is not installed.");
    const data = await this.readCommand(executable, ["session", "list", "--format", "json", "--max-count", String(MAX_DISCOVERY)]);
    if (!Array.isArray(data)) throw new Error("OpenCode returned an unsupported session list format.");
    const namespace = Bun.env.XDG_DATA_HOME || join(homedir(), ".local", "share");
    const chats: ExternalChat[] = [];
    let skipped = 0;
    const supportsResume = await this.supportsResume(executable);
    for (const raw of data) {
      const row = record(raw); const id = text(row.id);
      if (row.parentID) continue;
      if (!/^ses_[a-zA-Z0-9_-]+$/.test(id)) { skipped++; continue; }
      const workspacePath = text(row.directory) || undefined;
      const available = await existingWorkspace(workspacePath);
      chats.push({ provider: this.provider, sourceId: id, sourceKey: nativeSourceKey(this.provider, id),
        title: title(row.title), createdAt: timestamp(record(row.time).created ?? row.created),
        updatedAt: timestamp(record(row.time).updated ?? row.updated), workspacePath,
        canResume: Boolean(available) && supportsResume,
        warning: !available ? "Original project folder is unavailable; history only."
          : !supportsResume ? "This OpenCode version does not expose saved-session loading; history only." : undefined });
    }
    return { chats, complete: data.length < MAX_DISCOVERY && skipped === 0,
      notices: data.length >= MAX_DISCOVERY ? [`OpenCode: history discovery reached its ${MAX_DISCOVERY} session safety limit.`] : [] };
  }
  async read(chat: ExternalChat) {
    const executable = await this.find();
    if (!executable) throw new Error("OpenCode is not installed.");
    return openCodeMessages(await this.readCommand(executable, ["export", chat.sourceId]), chat.createdAt);
  }
}

export function openCodeMessages(data: unknown, fallbackDate: number): ImportedMessage[] {
  const root = record(data);
  if (!Array.isArray(root.messages)) throw new Error("OpenCode returned an unsupported transcript format.");
  const messages: ImportedMessage[] = [];
  for (const raw of root.messages) {
    const row = record(raw); const info = record(row.info);
    if (!["user", "assistant"].includes(info.role)) continue;
    const parts: MessagePart[] = (Array.isArray(row.parts) ? row.parts : []).flatMap((part: any) => {
      if (part.type !== "tool") return contentParts([part]);
      const state = record(part.state);
      return [toolPart(text(part.tool), state.input, { id: text(part.callID) || undefined,
        output: text(state.output) || text(state.error), status: state.status === "error" ? "failed" : "completed" })];
    });
    if (parts.length) messages.push({ role: info.role, content: readableText(parts), parts, createdAt: timestamp(record(info.time).created, fallbackDate) });
  }
  return normalizeMessages(messages);
}
