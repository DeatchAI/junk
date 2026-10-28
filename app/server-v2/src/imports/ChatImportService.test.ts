import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SqliteHistory } from "../history/SqliteHistory";
import { ChatImportService } from "./ChatImportService";
import { resolveHistorySession } from "./ResumeSession";
import type { ExternalChat, ImportedMessage, ImportSource } from "./ImportTypes";

const dirs: string[] = [];
afterEach(() => { for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true }); });
function setup() {
  const root = mkdtempSync(join(tmpdir(), "detach-import-tests-")); dirs.push(root);
  const path = join(root, "history.db"); const history = new SqliteHistory(path);
  const chat: ExternalChat = { provider: "codex", sourceId: "native-id", sourceKey: "codex-key", title: "Keyboard navigation",
    createdAt: 1000, updatedAt: 2000, workspacePath: root, canResume: true, locator: "/private/not-exposed" };
  const messages: ImportedMessage[] = [{ role: "user", content: "Add keyboard navigation", createdAt: 1000 }, { role: "assistant", content: "Done", createdAt: 2000 }];
  const source: ImportSource = { provider: "codex", discover: async () => ({ chats: [chat] }), read: async () => messages };
  const service = new ChatImportService(history, [source]);
  return { root, path, history, chat, messages, source, service };
}

describe("chat migration", () => {
  test("opt-in scan issues private tickets; preview/import require the same client", async () => {
    const { service, history } = setup(); const client = {}; const other = {};
    const { candidates } = await service.discover(client);
    expect(candidates).toHaveLength(1);
    expect(JSON.stringify(candidates)).not.toContain("native-id");
    expect(JSON.stringify(candidates)).not.toContain("not-exposed");
    expect(history.list()).toHaveLength(0);
    await expect(service.preview(other, candidates[0]!.id)).rejects.toThrow();
    await expect(service.import(client, ["/etc/passwd"])).rejects.toThrow();
    const preview = await service.preview(client, candidates[0]!.id);
    expect(preview.messageCount).toBe(2);
    expect(history.list()).toHaveLength(0);
  });

  test("transactional import preserves title/dates, search, provider and native resume after restart", async () => {
    const { service, path, history, root } = setup(); const client = {};
    const { candidates } = await service.discover(client);
    expect(await service.import(client, [candidates[0]!.id])).toMatchObject({ imported: 1, skipped: 0, errors: [] });
    const reopened = new SqliteHistory(path); const conversation = reopened.list()[0]!;
    expect(conversation).toMatchObject({ title: "Keyboard navigation", provider: "codex", created_at: 1000, updated_at: 2000,
      workspacePath: root, importSource: { provider: "codex", canResume: true } });
    expect(reopened.get(conversation.id)?.messages.map((message) => message.created_at)).toEqual([1000, 2000]);
    expect(reopened.search("navigation")).toHaveLength(1);
    expect(reopened.claimTitleGeneration(conversation.id)).toBeUndefined();
    expect(await resolveHistorySession(history, { type: "chat", text: "Next", conversationId: conversation.id }, "codex"))
      .toEqual({ id: "native-id", workspacePath: root });
    expect(await resolveHistorySession(history, { type: "chat", text: "Next", conversationId: conversation.id }, "claude")).toBeUndefined();
  });

  test("repeat scans and imports skip duplicates; removing from Detach never deletes provider history", async () => {
    const { service, history } = setup(); const client = {};
    const first = (await service.discover(client)).candidates[0]!;
    await service.import(client, [first.id, first.id]);
    const second = (await service.discover(client)).candidates[0]!;
    expect(second.imported).toBe(true);
    expect(await service.import(client, [second.id])).toMatchObject({ imported: 0, skipped: 1 });
    history.deleteConversation(history.list()[0]!.id);
    expect((await service.discover(client)).candidates[0]!.imported).toBe(false);
    expect(await service.import(client, [(await service.discover(client)).candidates[0]!.id])).toMatchObject({ imported: 1 });
  });

  test("partial failure is explicit and creates no empty conversation", async () => {
    const { service, source, chat, history } = setup(); const client = {};
    source.discover = async () => ({ chats: [chat, { ...chat, sourceId: "bad", sourceKey: "bad" }] });
    source.read = async (item) => { if (item.sourceId === "bad") throw new Error("secret-path-do-not-leak"); return [{ role: "user", content: "Hello", createdAt: 1000 }]; };
    const result = await service.import(client, (await service.discover(client)).candidates.map((candidate) => candidate.id));
    expect(result.imported).toBe(1); expect(result.errors).toHaveLength(1);
    expect(JSON.stringify(result)).not.toContain("secret-path");
    expect(history.list()).toHaveLength(1);
  });

  test("history-only imports do not acquire native bindings; edited native history loses the binding", async () => {
    const { service, source, chat, history } = setup(); const client = {};
    source.discover = async () => ({ chats: [chat, { ...chat, sourceKey: "history-only", canResume: false }] });
    await service.import(client, (await service.discover(client)).candidates.map((candidate) => candidate.id));
    const entries = history.list();
    const native = entries.find((entry) => entry.importSource?.canResume)!;
    const readonly = entries.find((entry) => !entry.importSource?.canResume)!;
    expect(history.metadata.session(readonly.id, "codex")).toBeUndefined();
    history.metadata.record(native.id, "claude");
    expect(history.get(native.id)?.conversation.importSource?.canResume).toBe(false);
    history.metadata.record(native.id, "codex");
    const message = history.get(native.id)!.messages[0]!;
    history.editMessage(message.id, "Different request");
    expect(history.metadata.session(native.id, "codex")).toBeUndefined();
    expect(history.get(native.id)?.conversation.importSource?.canResume).toBe(false);
  });

  test("native resume refuses a different or missing workspace and ignores client-supplied IDs", async () => {
    const { service, history, root } = setup(); const client = {};
    await service.import(client, (await service.discover(client)).candidates.map((candidate) => candidate.id));
    const conversationId = history.list()[0]!.id;
    await expect(resolveHistorySession(history, { type: "chat", text: "Next", conversationId, workspacePath: "/elsewhere" }, "codex")).rejects.toThrow("another project");
    expect(await resolveHistorySession(history, { type: "chat", text: "Next", providerSessionId: "forged" }, "codex")).toBeUndefined();
    history.metadata.bind(conversationId, "codex", { id: "native-id", workspacePath: join(root, "deleted-folder") });
    await expect(resolveHistorySession(history, { type: "chat", text: "Next", conversationId }, "codex")).rejects.toThrow("unavailable");
  });

  test("history-only chats without an original folder require an explicit valid folder", async () => {
    const { source, chat, service, history, root } = setup(); const client = {};
    source.discover = async () => ({ chats: [{ ...chat, canResume: false, workspacePath: undefined }] });
    await service.import(client, (await service.discover(client)).candidates.map((candidate) => candidate.id));
    const conversationId = history.list()[0]!.id;
    await expect(resolveHistorySession(history, { type: "chat", text: "Next", conversationId }, "codex")).rejects.toThrow("working folder");
    expect(await resolveHistorySession(history, { type: "chat", text: "Next", conversationId, workspacePath: root }, "codex")).toBeUndefined();
  });
});
