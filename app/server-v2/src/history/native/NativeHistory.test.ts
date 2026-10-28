import { describe, expect, test } from "bun:test";
import { mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SqliteHistory } from "../SqliteHistory";
import type { ExternalChat, ImportedMessage, ImportSource } from "../../imports/ImportTypes";
import { nativeConversationID, nativeSourceKey } from "./NativeIdentity";
import { NativeHistoryIndex } from "./NativeHistoryIndex";
import { NativeHistoryService } from "./NativeHistoryService";
import { NativeRunContext } from "./NativeRunContext";

async function idle(service: NativeHistoryService) {
  for (let i = 0; i < 1000 && service.status.indexing; i++) await Bun.sleep(2);
  expect(service.status.indexing).toBe(false);
}
async function fixture(run: (value: { directory: string; index: NativeHistoryIndex; legacy: SqliteHistory }) => Promise<void>) {
  const directory = await mkdtemp(join(tmpdir(), "detach-native-index-"));
  const index = new NativeHistoryIndex(join(directory, "index.sqlite"));
  const legacy = new SqliteHistory(join(directory, "legacy.sqlite"));
  try { await run({ directory, index, legacy }); }
  finally { index.close(); await rm(directory, { recursive: true, force: true }); }
}
const saved = (id: string, workspace = process.cwd()): ExternalChat => ({ provider: "claude", sourceId: id,
  sourceKey: nativeSourceKey("claude", id), title: `Task ${id}`, createdAt: 1000, updatedAt: 2000,
  workspacePath: workspace, canResume: true });
const transcript: ImportedMessage[] = [{ role: "user", content: "Original task", createdAt: 1000 },
  { role: "assistant", content: "Searchable nebula-keyword answer", createdAt: 2000 }];

describe("provider-owned history", () => {
  test("identity is stable across canonical paths and distinct across stores and providers", async () => {
    await fixture(async ({ directory }) => {
      await symlink(directory, join(directory, "alias"));
      expect(nativeSourceKey("codex", "same", directory)).toBe(nativeSourceKey("codex", "same", join(directory, "alias")));
      expect(nativeSourceKey("claude", "same", directory)).not.toBe(nativeSourceKey("codex", "same", directory));
      expect(nativeSourceKey("codex", "same", "/different-store")).not.toBe(nativeSourceKey("codex", "same", directory));
    });
  });
  test("derived index searches content, respects hides, and never changes source messages", async () => {
    await fixture(async ({ index }) => {
      const source = saved("a"); const id = index.cache(source, transcript).conversation.id;
      expect(index.search("nebula")[0]?.conversation_id).toBe(id);
      index.rememberMCPs(id, ["browser"]); index.hide(id);
      expect(index.list()).toHaveLength(0); expect(index.search("nebula")).toHaveLength(0);
      index.restoreHidden(); expect(index.mcpIDs(id)).toEqual(["browser"]);
      index.upsert({ ...source, title: "Provider renamed this" });
      expect(index.list()).toHaveLength(1); expect(index.get(id)?.conversation.title).toBe("Provider renamed this");
      expect(transcript[1]!.content).toBe("Searchable nebula-keyword answer");
      index.cache(saved("many"), Array.from({ length: 400 }, (_, i) => ({ role: "assistant" as const, content: `nebula result ${i}`, createdAt: 2000 + i })));
      expect(index.searchChats("nebula")).toHaveLength(2);
    });
  });
  test("automatic discovery is idempotent, indexes all pages, and rebuilds without legacy copies", async () => {
    await fixture(async ({ directory, index, legacy }) => {
      const chats = Array.from({ length: 503 }, (_, i) => ({ ...saved(String(i)), updatedAt: 2000 + i }));
      const source: ImportSource = { provider: "claude", async discover() { return { chats, complete: true }; }, async read() { return transcript; } };
      const service = new NativeHistoryService(index, legacy, [source]);
      await service.refresh(true); await idle(service);
      await service.refresh(true); await idle(service);
      expect(service.list().conversations).toHaveLength(500); expect(service.list().hasMore).toBe(true);
      expect(service.list(500, 500).conversations).toHaveLength(3);
      expect(service.list(503, 0, true).conversations).toHaveLength(503);
      expect(service.search("Task 0").some((chat) => chat.id === nativeConversationID(chats[0]!.sourceKey))).toBe(true);
      expect(service.search("nebula")).toHaveLength(100); expect(legacy.list()).toHaveLength(0);
      const rebuilt = new NativeHistoryIndex(join(directory, "rebuilt.sqlite"));
      const other = new NativeHistoryService(rebuilt, legacy, [source]);
      await other.refresh(true); await idle(other);
      expect(other.list().conversations.map((chat) => chat.id)).toEqual(service.list().conversations.map((chat) => chat.id));
      other.stop(); rebuilt.close(); service.stop();
    });
  });
  test("external renames and messages win; unavailable or partial sources do not purge cached chats", async () => {
    await fixture(async ({ index, legacy }) => {
      let chats = [saved("a"), saved("b")]; let failed = false, complete = true;
      let messages = transcript;
      const source: ImportSource = { provider: "claude", async discover() {
        if (failed) throw new Error("offline"); return { chats, complete };
      }, async read() { if (failed) throw new Error("offline"); return messages; } };
      const service = new NativeHistoryService(index, legacy, [source]);
      await service.refresh(true); await idle(service);
      chats = [{ ...chats[0]!, title: "External rename", updatedAt: 3000 }]; complete = false;
      messages = [...transcript, { role: "user", content: "External follow-up", createdAt: 3000 }];
      await service.refresh(true); await idle(service);
      expect(service.list().conversations).toHaveLength(2);
      expect((await service.get(nativeConversationID(chats[0]!.sourceKey)))?.messages.at(-1)?.content).toBe("External follow-up");
      expect(service.list().conversations[0]?.title).toBe("External rename");
      failed = true; await service.refresh(true);
      const offline = await service.get(nativeConversationID(chats[0]!.sourceKey));
      expect(offline?.messages.length).toBe(3); expect(offline?.conversation.canResume).toBe(false);
      expect(service.list().conversations).toHaveLength(2);
      failed = false; complete = true; await service.refresh(true); await idle(service);
      expect(service.list().conversations).toHaveLength(1); service.stop();
    });
  });
  test("resume uses a real binding without replay; legacy continuation creates a new native identity", async () => {
    await fixture(async ({ directory, index, legacy }) => {
      const chat = { ...saved("original", directory), locator: "/fixture/original.jsonl" };
      const source: ImportSource = { provider: "claude", async discover() { return { chats: [chat] }; }, async read() { return transcript; } };
      const service = new NativeHistoryService(index, legacy, [source]);
      const id = index.cache(chat, transcript).conversation.id;
      const request = { type: "chat" as const, text: "Continue", conversationId: id, agent: "claude" as const };
      const frame = await NativeRunContext.prepare(service, legacy, request, "claude", "run");
      expect(frame.nativeSessionID).toBe("original"); expect(frame.nativeSessionPath).toBe(chat.locator);
      expect(frame.contextMessages).toEqual([]);
      await expect(NativeRunContext.prepare(service, legacy, request, "claude", "other")).rejects.toThrow("already running");
      expect(() => frame.bind({ id: "wrong" })).toThrow("different session");
      frame.bind({ id: "original" }); frame.cacheResponse("Provider response");
      expect(index.get(id)?.messages.at(-1)?.content).toBe("Provider response");
      await frame.release();
      const old = legacy.addUserMessage(undefined, "Legacy context").conversation;
      legacy.addAssistantMessage(old.id, "Legacy reply");
      const oldSnapshot = legacy.get(old.id);
      const migrated = await NativeRunContext.prepare(service, legacy, { type: "chat", text: "Continue legacy", conversationId: old.id,
        workspacePath: directory }, "claude", "legacy-run");
      expect(migrated.nativeSessionID).toBeUndefined(); expect(migrated.contextMessages).toHaveLength(2);
      migrated.bind({ id: "new-native", path: "/fixture/new.jsonl" }); migrated.cacheResponse("New response");
      expect(migrated.conversation.id).not.toBe(old.id); expect(legacy.get(old.id)).toEqual(oldSnapshot);
      expect(service.list().conversations.find((entry) => entry.id === old.id)?.origin).toBe("legacy");
      await migrated.release(); service.stop();
    });
  });
  test("unknown, active, wrong-provider and wrong-workspace resumes fail closed", async () => {
    await fixture(async ({ directory, index, legacy }) => {
      const service = new NativeHistoryService(index, legacy, []);
      const chat = saved("guarded", directory); const id = index.upsert(chat);
      await expect(NativeRunContext.prepare(service, legacy, { type: "chat", text: "x", conversationId: "forged" }, "claude", "1")).rejects.toThrow("unavailable");
      await expect(NativeRunContext.prepare(service, legacy, { type: "chat", text: "x", conversationId: id }, "codex", "2")).rejects.toThrow("claude session");
      await expect(NativeRunContext.prepare(service, legacy, { type: "chat", text: "x", conversationId: id, workspacePath: process.cwd() }, "claude", "3")).rejects.toThrow("another project");
      index.upsert({ ...chat, active: true });
      await expect(NativeRunContext.prepare(service, legacy, { type: "chat", text: "x", conversationId: id }, "claude", "4")).rejects.toThrow("another client");
      service.stop();
    });
  });
});
