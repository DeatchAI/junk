import { contentParts, readableText, activityPart } from "../../imports/TranscriptParts";
import { readdir, realpath, stat } from "node:fs/promises";
import { join, sep } from "node:path";
import { findExecutable } from "../../runtime/CapabilityDetector";
import type { ExternalChat, ImportedMessage, ImportSource } from "../../imports/ImportTypes";
import { contentText, existingWorkspace, MAX_DISCOVERY, MAX_TRANSCRIPT_BYTES, normalizeMessages, parseLines, record, text, timestamp, title, transcriptLines } from "../../imports/Transcript";
import { nativeSourceKey, providerHistoryRoot } from "./NativeIdentity";
import { supportsACPSessionLoad } from "../../imports/ReadOnlyProcess";

/** Pi and Omp publish compatible tree envelopes, not Claude's message schema. */
export class FileSessionSource implements ImportSource {
  constructor(readonly provider: "pi" | "omp", private readonly root = providerHistoryRoot(provider),
    private readonly find = () => findExecutable(provider), private readonly supportsResume = supportsACPSessionLoad) {}
  async discover() {
    const root = await realpath(this.root);
    const files: { path: string; updated: number }[] = [];
    let skipped = 0;
    const addFile = async (path: string) => {
      const info = await stat(path);
      if (info.size <= MAX_TRANSCRIPT_BYTES) files.push({ path, updated: Math.round(info.mtimeMs) });
      else skipped++;
    };
    for (const entry of await readdir(root, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.endsWith(".jsonl")) { await addFile(join(root, entry.name)); continue; }
      if (!entry.isDirectory() || entry.isSymbolicLink()) continue;
      for (const file of await readdir(join(root, entry.name), { withFileTypes: true })) {
        if (!file.isFile() || !file.name.endsWith(".jsonl")) continue;
        await addFile(join(root, entry.name, file.name));
      }
    }
    files.sort((a, b) => b.updated - a.updated);
    const executable = await this.find();
    const resumable = executable && (this.provider === "pi" || await this.supportsResume(executable));
    const chats: ExternalChat[] = [];
    for (const file of files.slice(0, MAX_DISCOVERY)) {
      try {
        const blob = Bun.file(file.path);
        const first = parseLines(await blob.slice(0, 128 * 1024).text());
        const tail = blob.size > 128 * 1024 ? parseLines(await blob.slice(-128 * 1024).text()) : first;
        const header = first.find((entry) => entry.type === "session");
        if (!header || !text(header.id) || text(header.id).length > 512) { skipped++; continue; }
        const named = [...first, ...tail].findLast((entry) => entry.type === "session_info" && entry.name);
        const slot = first.find((entry) => entry.type === "title");
        const prompt = first.find((entry) => entry.type === "message" && record(entry.message).role === "user");
        const workspace = text(header.cwd); const available = await existingWorkspace(workspace);
        chats.push({ provider: this.provider, sourceId: text(header.id), sourceKey: nativeSourceKey(this.provider, text(header.id), root),
          locator: file.path, title: title((this.provider === "omp" ? slot?.title : undefined) || named?.name || header.title || contentText(record(prompt?.message).content)),
          createdAt: timestamp(header.timestamp, file.updated), updatedAt: file.updated, workspacePath: workspace || undefined,
          canResume: Boolean(available) && Boolean(resumable),
          warning: !available ? "Project folder is unavailable." : !executable ? "Provider CLI is not installed."
            : !resumable ? "This provider version does not expose saved-session loading." : undefined });
      } catch { skipped++; }
    }
    return { chats, complete: files.length < MAX_DISCOVERY && skipped === 0,
      notices: [...(files.length >= MAX_DISCOVERY ? [`${this.provider}: history discovery reached its ${MAX_DISCOVERY} session safety limit.`] : []),
        ...(skipped ? [`${this.provider}: ${skipped} unsupported or oversized sessions were not indexed.`] : [])] };
  }
  async read(chat: ExternalChat) {
    const root = await realpath(this.root); const path = await realpath(chat.locator ?? "");
    if (!path.startsWith(root + sep) || !path.endsWith(".jsonl")) throw new Error("Session is outside the provider's history folder.");
    if ((await stat(path)).size > MAX_TRANSCRIPT_BYTES) throw new Error("Session is too large to index.");
    return treeSessionMessages(await Bun.file(path).text(), chat.createdAt);
  }
}

export function treeSessionMessages(value: string, fallback: number): ImportedMessage[] {
  const entries = transcriptLines(value).filter((entry) => entry.id && entry.type !== "session");
  const byID = new Map(entries.map((entry) => [entry.id, entry]));
  const branch = new Set<string>(); let current = entries.at(-1);
  while (current?.id && !branch.has(current.id)) { branch.add(current.id); current = byID.get(current.parentId); }
  const messages: ImportedMessage[] = [];
  for (const entry of entries) {
    if (branch.size && !branch.has(entry.id)) continue;
    const message = record(entry.message); const role = message.role;
    if (entry.type !== "message" || !["user", "assistant", "toolResult"].includes(role)) continue;
    const parts = role === "toolResult" ? [activityPart("tool", "Tool result", {
      id: text(message.toolCallId) || undefined, toolName: text(message.toolName) || undefined,
      output: contentText(message.content), status: message.isError ? "failed" : "completed",
    })] : contentParts(message.content);
    if (parts.length) messages.push({ role: role === "user" ? "user" : "assistant", content: readableText(parts), parts,
      createdAt: timestamp(entry.timestamp ?? message.timestamp, fallback) });
  }
  return normalizeMessages(messages);
}
