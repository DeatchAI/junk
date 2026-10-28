import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SqliteHistory } from "../history/SqliteHistory";
import { ConversationTitleService, type ConversationTitleUpdate, type TitleRequest } from "./ConversationTitleService";

describe("background chat naming", () => {
  test("one job per chat; first prompt and selected provider; metadata only", async () => {
    const history = new SqliteHistory(":memory:");
    const { conversation } = history.addUserMessage(undefined, "Please fix the chat approval UI");
    const requests: TitleRequest[] = [], events: ConversationTitleUpdate[] = [];
    const pending = Promise.withResolvers<string>();
    const service = new ConversationTitleService(history, (request) => { requests.push(request); return pending.promise; },
      (update) => events.push(update));
    const first = service.schedule(conversation.id, "claude", "opus");
    expect(service.schedule(conversation.id, "codex", "expensive")).toBe(first);
    await Promise.resolve();
    expect(requests).toEqual([{ agent: "claude", model: "opus", message: "Please fix the chat approval UI" }]);
    history.addUserMessage(conversation.id, "Focus on keyboard navigation");
    pending.resolve("Polish Chat Approval Controls");
    await first;
    expect(history.get(conversation.id)?.conversation.title).toBe("Polish Chat Approval Controls");
    expect(events).toEqual([{ type: "conversation_title", conversationId: conversation.id, title: "Polish Chat Approval Controls" }]);
    await service.schedule(conversation.id, "codex");
    expect(requests).toHaveLength(1);
    expect(history.get(conversation.id)?.messages).toHaveLength(2);
  });
  test("errors retain the fallback and do not fail the main task", async () => {
    for (const generate of [async () => { throw new Error("Not logged in"); }, async () => "Here is the title",
      async () => "x".repeat(200), async () => undefined]) {
      const history = new SqliteHistory(":memory:");
      const { conversation } = history.addUserMessage(undefined, "Fix task approvals");
      let events = 0;
      const service = new ConversationTitleService(history, generate, () => { events += 1; });
      await service.schedule(conversation.id, "codex");
      await service.schedule(conversation.id, "codex");
      expect(history.get(conversation.id)?.conversation.title).toBe(conversation.title);
      expect(events).toBe(0);
      history.addAssistantMessage(conversation.id, "Main task completed normally.");
      expect(history.get(conversation.id)?.messages).toHaveLength(2);
    }
  });
  test("late title results never resurrect deleted chats", async () => {
    const history = new SqliteHistory(":memory:");
    const { conversation } = history.addUserMessage(undefined, "Temporary task");
    const deferred = Promise.withResolvers<string>(), events: unknown[] = [];
    const service = new ConversationTitleService(history, () => deferred.promise, (event) => events.push(event));
    const task = service.schedule(conversation.id, "pi");
    history.deleteConversation(conversation.id);
    deferred.resolve("Name Deleted Conversation");
    await task;
    expect(history.get(conversation.id)).toBeUndefined();
    expect(events).toHaveLength(0);
  });
  test("fx uses its native title, not a second inference request", async () => {
    const history = new SqliteHistory(":memory:");
    const { conversation } = history.addUserMessage(undefined, "Improve the Mac side notch");
    let generated = 0;
    const events: unknown[] = [];
    const service = new ConversationTitleService(history, async () => { generated += 1; return ""; },
      (event) => events.push(event));
    await service.schedule(conversation.id, "fx");
    service.acceptProviderTitle(conversation.id, "Polish Mac Side Notch");
    service.acceptProviderTitle(conversation.id, "A Late Duplicate Name");
    expect(generated).toBe(0);
    expect(events).toHaveLength(1);
    expect(history.get(conversation.id)?.conversation.title).toBe("Polish Mac Side Notch");
  });
  test("migrates existing DBs, persists names, and does not overwrite custom renames", async () => {
    const directory = mkdtempSync(join(tmpdir(), "detach-title-db-test-"));
    try {
      const path = join(directory, "history.sqlite");
      const db = new Database(path);
      db.exec("CREATE TABLE conversations (id TEXT PRIMARY KEY, title TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)");
      db.close();
      const history = new SqliteHistory(path);
      const { conversation } = history.addUserMessage(undefined, "Polish the side notch");
      const deferred = Promise.withResolvers<string>();
      const service = new ConversationTitleService(history, () => deferred.promise, () => {});
      const task = service.schedule(conversation.id, "omp");
      const external = new Database(path);
      external.run("UPDATE conversations SET title = ? WHERE id = ?", ["My own name", conversation.id]);
      deferred.resolve("Replace With Generated Name");
      await task;
      expect(new SqliteHistory(path).get(conversation.id)?.conversation.title).toBe("My own name");
      const other = history.addUserMessage(undefined, "Fix settings saving").conversation;
      const namer = new ConversationTitleService(history, async () => "Fix Settings Persistence", () => {});
      await namer.schedule(other.id, "codex");
      const reopened = new SqliteHistory(path);
      expect(reopened.get(other.id)?.conversation.title).toBe("Fix Settings Persistence");
      expect(reopened.get(other.id)?.conversation.updated_at).toBe(other.updated_at);
      external.close();
    } finally { rmSync(directory, { recursive: true, force: true }); }
  });
});
