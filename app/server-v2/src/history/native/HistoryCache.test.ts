import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { NativeHistoryIndex } from "./NativeHistoryIndex";
import { NativeHistoryService } from "./NativeHistoryService";
import { SqliteHistory } from "../SqliteHistory";
import { nativeConversationID, nativeSourceKey } from "./NativeIdentity";
import type { ExternalChat, ImportSource, ImportedMessage } from "../../imports/ImportTypes";

const chat: ExternalChat = { provider: "claude", sourceId: "cache-fixture", sourceKey: nativeSourceKey("claude", "cache-fixture"),
  title: "Fixture", workspacePath: "/fixture", createdAt: 1, updatedAt: 2, canResume: true, locator: "/fixture/provider-owned" };
const messages: ImportedMessage[] = [{ role: "user", content: "Private searchable unicorn", createdAt: 1 }];

async function fixture(run: (index: NativeHistoryIndex, service: NativeHistoryService) => Promise<void>, read = async () => messages) {
  const directory = await mkdtemp(join(tmpdir(), "detach-cache-policy-"));
  const index = new NativeHistoryIndex(join(directory, "index.sqlite"));
  const legacy = new SqliteHistory(join(directory, "legacy.sqlite"));
  const source: ImportSource = { provider: "claude", async discover() { return { chats: [chat], complete: true }; }, read };
  const service = new NativeHistoryService(index, legacy, [source]);
  index.upsert(chat);
  try { await run(index, service); }
  finally { service.stop(); index.close(); await rm(directory, { recursive: true, force: true }); }
}

test("disabling cache removes searchable text while keeping provider identities and preferences", async () => {
  await fixture(async (index, service) => {
    const id = nativeConversationID(chat.sourceKey);
    index.cache(chat, messages);
    index.rememberMCPs(id, ["browser"]);
    index.hide(id);
    expect(index.cacheStatus.cachedMessages).toBe(1);
    service.configureSearchCache(false);
    expect(index.cacheStatus).toEqual({ enabled: false, cachedMessages: 0, cachedChats: 0, bytes: 0 });
    expect(index.search("unicorn")).toEqual([]);
    expect(index.source(id)?.sourceId).toBe(chat.sourceId);
    expect(index.isHidden(chat.sourceKey)).toBe(true);
    expect(index.mcpIDs(id)).toEqual(["browser"]);
    const opened = await service.get(id);
    expect(opened?.messages[0]?.content).toBe(messages[0]!.content);
    expect(opened?.conversation.canResume).toBe(true);
    expect(index.cacheStatus.cachedMessages).toBe(0);
    index.cache(chat, messages);
    expect(index.cacheStatus.cachedMessages).toBe(0);
  });
});

test("clearing cache invalidates readers already in flight", async () => {
  let resolveRead!: (value: ImportedMessage[]) => void;
  const gate = new Promise<ImportedMessage[]>((resolve) => { resolveRead = resolve; });
  await fixture(async (index, service) => {
    const pending = service.readSource(chat);
    service.clearSearchCache();
    resolveRead(messages);
    expect((await pending).messages[0]?.content).toBe(messages[0]!.content);
    expect(index.cacheStatus.cachedMessages).toBe(0);
    expect(index.search("unicorn")).toEqual([]);
    expect(index.cacheStatus.enabled).toBe(true);
  }, () => gate);
});

test("disabled cache policy survives reopening its local index", async () => {
  const directory = await mkdtemp(join(tmpdir(), "detach-cache-restart-"));
  const path = join(directory, "index.sqlite");
  try {
    let index = new NativeHistoryIndex(path);
    index.setSearchCacheEnabled(false); index.close();
    index = new NativeHistoryIndex(path);
    expect(index.searchCacheEnabled).toBe(false);
    expect(index.cache(chat, messages).messages).toHaveLength(1);
    expect(index.cacheStatus.cachedMessages).toBe(0);
    index.setSearchCacheEnabled(true);
    index.cache(chat, messages);
    expect(index.search("unicorn")).toHaveLength(1);
    index.close();
  } finally { await rm(directory, { recursive: true, force: true }); }
});
