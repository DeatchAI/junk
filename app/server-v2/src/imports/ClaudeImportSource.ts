import { contentParts, readableText } from "./TranscriptParts";
import { readdir, realpath, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join, sep } from "node:path";
import { findExecutable } from "../runtime/CapabilityDetector";
import { nativeSourceKey } from "../history/native/NativeIdentity";
import type { ExternalChat, ImportedMessage, ImportSource } from "./ImportTypes";
import { contentText, existingWorkspace, MAX_DISCOVERY, MAX_TRANSCRIPT_BYTES, normalizeMessages, parseLines, record, text, timestamp, title, transcriptLines } from "./Transcript";

/** Claude's JSONL is versioned defensively; unknown event types are never executed. */
export class ClaudeImportSource implements ImportSource {
  readonly provider = "claude" as const;
  constructor(private readonly projects = join(Bun.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude"), "projects"),
    private readonly find = () => findExecutable("claude")) {}
  async discover() {
    const root = await realpath(this.projects).catch(() => undefined);
    if (!root) throw new Error("Claude Code history folder is unavailable.");
    const files: { path: string; modified: number }[] = [];
    let skipped = 0;
    const directories = await readdir(root, { withFileTypes: true });
    for (const directory of directories) {
      if (!directory.isDirectory() || directory.isSymbolicLink()) continue;
      const folder = join(root, directory.name);
      for (const file of await readdir(folder, { withFileTypes: true }).catch(() => [])) {
        if (!file.isFile() || !/\.jsonl$/i.test(file.name)) continue;
        const path = join(folder, file.name); const info = await stat(path).catch(() => undefined);
        if (info?.size && info.size <= MAX_TRANSCRIPT_BYTES) files.push({ path, modified: info.mtimeMs });
        else if (info?.size) skipped++;
      }
    }
    files.sort((a, b) => b.modified - a.modified);
    const chats: ExternalChat[] = [];
    const installed = Boolean(await this.find());
    for (const file of files.slice(0, MAX_DISCOVERY)) {
      try {
      const transcript = Bun.file(file.path);
      let rows = parseLines(await transcript.slice(0, 65_536).text());
      if (!rows.some((row) => row.type === "user" && !row.isSidechain)) rows = parseLines(await transcript.text());
      const tail = transcript.size > 65_536 ? parseLines(await transcript.slice(-65_536).text()) : rows;
      const all = [...rows, ...tail];
      const first = rows.find((row) => row.type === "user" && !row.isSidechain && contentText(record(row.message).content));
      // A native fork may retain ancestor rows with the parent's sessionId.
      const id = basename(file.path, ".jsonl");
      if (!/^[a-zA-Z0-9_-]{8,120}$/.test(id) || !first) { skipped++; continue; }
      const workspacePath = text(first.cwd) || undefined;
      const available = await existingWorkspace(workspacePath);
      const custom = all.findLast((row) => row.type === "custom-title");
      const summary = all.findLast((row) => row.type === "summary");
      const assistant = all.findLast((row) => row.type === "assistant" && record(row.message).model);
      chats.push({ provider: this.provider, sourceId: id, sourceKey: nativeSourceKey(this.provider, id, root), locator: file.path,
        title: title(custom?.customTitle || summary?.summary || contentText(record(first.message).content)),
        createdAt: timestamp(first.timestamp, Math.round(file.modified)), updatedAt: Math.round(file.modified),
        workspacePath, model: text(record(assistant?.message).model) || undefined,
        canResume: Boolean(available) && installed, warning: !available ? "Original project folder is unavailable; history only."
          : !installed ? "Claude Code is not installed; history only." : undefined });
      } catch { skipped++; }
    }
    const notices = files.length >= MAX_DISCOVERY ? [`Claude Code: history discovery reached its ${MAX_DISCOVERY} session safety limit.`] : [];
    if (skipped) notices.push(`Claude Code: ${skipped} unsupported or oversized transcripts were not included.`);
    return { chats, notices, complete: files.length < MAX_DISCOVERY && skipped === 0 };
  }
  async read(chat: ExternalChat) {
    const root = await realpath(this.projects);
    const path = await realpath(chat.locator ?? "");
    if (!path.startsWith(root + sep) || !path.endsWith(".jsonl")) throw new Error("Transcript is outside the selected Claude history source.");
    const info = await stat(path);
    if (!info.isFile() || info.size > MAX_TRANSCRIPT_BYTES) throw new Error("Claude transcript is unavailable or too large.");
    return claudeMessages(await Bun.file(path).text(), chat.createdAt);
  }
}

export function claudeMessages(value: string, fallbackDate: number): ImportedMessage[] {
  const rows = transcriptLines(value).filter((row) => !row.isSidechain);
  const entries = rows.filter((row) => ["user", "assistant"].includes(row.type) && row.message);
  // A resumed/branched transcript may contain abandoned paths. Follow only the current leaf.
  const byId = new Map(rows.filter((row) => row.uuid).map((row) => [row.uuid, row]));
  const leaf = entries.at(-1); const branch = new Set<string>();
  let pointer = leaf;
  while (pointer?.uuid && !branch.has(pointer.uuid)) {
    branch.add(pointer.uuid); pointer = byId.get(pointer.parentUuid);
  }
  const result: ImportedMessage[] = [];
  let previousAssistant: string | undefined;
  let seenUser = false;
  for (const row of entries) {
    if (branch.size && row.uuid && !branch.has(row.uuid)) continue;
    const message = record(row.message);
    const parts = contentParts(message.content);
    const content = readableText(parts);
    if (!parts.length) continue;
    const blocks = Array.isArray(message.content) ? message.content : [];
    const toolOnly = blocks.length > 0 && blocks.every((block: any) => block.type === "tool_result");
    const role = row.type === "assistant" || toolOnly ? "assistant" : "user";
    const branchPoint = role === "user" ? (!seenUser ? { kind: "start" as const }
      : previousAssistant ? { kind: "claude" as const, resumeSessionAt: previousAssistant } : undefined) : undefined;
    result.push({ role, content, parts, branchPoint, createdAt: timestamp(row.timestamp, fallbackDate) });
    if (role === "user") seenUser = true;
    if (row.type === "assistant" && typeof row.uuid === "string") previousAssistant = row.uuid;
  }
  return normalizeMessages(result);
}
