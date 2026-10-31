import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SqliteHistory } from "../SqliteHistory";
import { NativeHistoryIndex } from "./NativeHistoryIndex";
import { NativeHistoryService } from "./NativeHistoryService";
import { NativeRunContext } from "./NativeRunContext";
import type { ExternalChat, ImportSource } from "../../imports/ImportTypes";

async function fixture(run: (index: NativeHistoryIndex, legacy: SqliteHistory, directory: string) => Promise<void>) {
  const directory = await mkdtemp(join(tmpdir(), "detach-discovery-race-"));
  const index = new NativeHistoryIndex(join(directory, "index.sqlite"));
  const legacy = new SqliteHistory(join(directory, "legacy.sqlite"));
  try { await run(index, legacy, directory); }
  finally { index.close(); await rm(directory, { recursive: true, force: true }); }
}

test("a refresh begun before a new task cannot delete its acknowledged session after completion", async () => {
  await fixture(async (index, legacy, directory) => {
    const pending = Promise.withResolvers<{ chats: ExternalChat[]; complete: boolean }>();
    let listed: ExternalChat[] | undefined;
    const source: ImportSource = { provider: "opencode", discover: () => listed ? Promise.resolve({ chats: listed, complete: true }) : pending.promise,
      async read() { return [{ role: "user", content: "Open Discord", createdAt: 1000 }]; } };
    const service = new NativeHistoryService(index, legacy, [source]);
    const refresh = service.refresh(true);
    await Promise.resolve();
    const frame = await NativeRunContext.prepare(service, legacy, { type: "chat", text: "Open Discord", workspacePath: directory }, "opencode", "run");
    frame.bind({ id: "ses_new", workspacePath: directory });
    frame.cacheResponse("Waiting for the update");
    await frame.release();
    pending.resolve({ chats: [], complete: true }); await refresh;
    expect(index.source(frame.conversation.id)?.sourceId).toBe("ses_new");
    listed = [index.source(frame.conversation.id)!]; await service.refresh(true);
    listed = []; await service.refresh(true);
    expect(index.source(frame.conversation.id)).toBeUndefined();
    service.stop();
  });
});

test("a follow-up recovers an indexed identity from provider metadata before rejecting it", async () => {
  await fixture(async (index, legacy, directory) => {
    let chat: ExternalChat;
    const source: ImportSource = { provider: "opencode", async discover() { return { chats: [chat], complete: true }; },
      async read() { return [{ role: "user", content: "Open Discord", createdAt: 1000 }]; } };
    const service = new NativeHistoryService(index, legacy, [source]);
    const id = service.register("opencode", "ses_existing", directory, "Open Discord");
    chat = index.source(id)!;
    await service.finish(id);
    index.reconcile("opencode", new Set()); // simulate an older version's project-scoped purge
    const frame = await NativeRunContext.prepare(service, legacy, { type: "chat", text: "What happened?", conversationId: id,
      workspacePath: directory }, "opencode", "follow-up");
    expect(frame.resumeSessionID).toBe("ses_existing");
    expect(frame.contextMessages).toEqual([]);
    await frame.release(); service.stop();
  });
});
