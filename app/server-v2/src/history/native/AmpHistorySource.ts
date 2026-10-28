import { contentParts, readableText } from "../../imports/TranscriptParts";
import { findExecutable } from "../../runtime/CapabilityDetector";
import { readHistoryCommand } from "../../imports/ReadOnlyProcess";
import { contentText, existingWorkspace, MAX_DISCOVERY, normalizeMessages, record, text, timestamp, title } from "../../imports/Transcript";
import type { ExternalChat, ImportSource } from "../../imports/ImportTypes";
import { nativeSourceKey } from "./NativeIdentity";

/** Unsupported CLI JSON versions remain unavailable, never parsed from terminal tables. */
export class AmpHistorySource implements ImportSource {
  readonly provider = "amp" as const;
  constructor(private readonly find = () => findExecutable("amp"), private readonly readCommand = readHistoryCommand) {}
  private async executable() {
    const path = await this.find(); if (!path) throw new Error("Amp is not installed."); return path;
  }
  async discover() {
    const result = await this.readCommand(await this.executable(), ["threads", "list", "--json"]);
    const rows = Array.isArray(result) ? result : record(result).threads;
    if (!Array.isArray(rows)) throw new Error("This Amp CLI does not expose a supported JSON thread list.");
    const chats: ExternalChat[] = []; let skipped = 0;
    for (const raw of rows.slice(0, MAX_DISCOVERY)) {
      const row = record(raw); const id = text(row.id ?? row.threadId);
      if (!/^T-[a-zA-Z0-9-]+$/.test(id)) { skipped++; continue; }
      const workspace = text(row.cwd ?? row.directory ?? row.workingDirectory);
      const available = await existingWorkspace(workspace);
      chats.push({ provider: this.provider, sourceId: id, sourceKey: nativeSourceKey(this.provider, id), title: title(row.title),
        createdAt: timestamp(row.createdAt ?? row.created), updatedAt: timestamp(row.updatedAt ?? row.updated), workspacePath: workspace || undefined,
        canResume: Boolean(available) && row.status !== "active", active: row.status === "active",
        warning: !available ? "Local project folder is unavailable; remote orbs are not attached by Detach." : undefined });
    }
    if (skipped && !chats.length) throw new Error("Unsupported Amp thread metadata.");
    return { chats, complete: rows.length < MAX_DISCOVERY && skipped === 0 && !record(result).nextCursor && record(result).hasMore !== true,
      notices: rows.length >= MAX_DISCOVERY ? [`Amp: history discovery reached its ${MAX_DISCOVERY} session safety limit.`] : [] };
  }
  async read(chat: ExternalChat) {
    const raw = await this.readCommand(await this.executable(), ["threads", "export", chat.sourceId]);
    const root = record(raw); const rows = root.messages ?? record(root.thread).messages;
    if (!Array.isArray(rows)) throw new Error("Unsupported Amp transcript format.");
    return normalizeMessages(rows.flatMap((raw) => {
      const row = record(raw); const message = record(row.message ?? row); const role = message.role;
      if (!["user", "assistant"].includes(role)) return [];
      const parts = contentParts(message.content);
      return parts.length ? [{ role, content: readableText(parts), parts, createdAt: timestamp(row.createdAt ?? row.timestamp, chat.createdAt) }] : [];
    }));
  }
}
