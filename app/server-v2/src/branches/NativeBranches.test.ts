import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SqliteHistory } from "../history/SqliteHistory";
import { NativeHistoryIndex } from "../history/native/NativeHistoryIndex";
import { NativeHistoryService } from "../history/native/NativeHistoryService";
import { NativeRunContext } from "../history/native/NativeRunContext";
import { nativeSourceKey } from "../history/native/NativeIdentity";
import type { ExternalChat, ImportedMessage, ImportSource } from "../imports/ImportTypes";
import { claudeMessages } from "../imports/ClaudeImportSource";
import { buildClaudeArgs } from "../agents/ClaudeAdapter";
import { withFixture } from "../agents/codex/fixtures/CodexFixtureHarness";
import { promptFingerprint } from "./BranchTypes";

test("native branches preserve the original, exclude the replaced turn and survive reindex/reopen", async () => {
  const dir = await mkdtemp(join(tmpdir(), "detach-branches-"));
  const path = join(dir, "index.sqlite");
  let index = new NativeHistoryIndex(path);
  const legacy = new SqliteHistory(join(dir, "legacy.sqlite"));
  const chat: ExternalChat = { provider: "codex", sourceId: "parent", sourceKey: nativeSourceKey("codex", "parent"),
    title: "Original", workspacePath: dir, canResume: true, createdAt: 1, updatedAt: 2 };
  const originals: ImportedMessage[] = [
    { role: "user", content: "First", createdAt: 1, branchPoint: { kind: "codex", beforeTurnId: "t1" } },
    { role: "assistant", content: "First answer", createdAt: 2 },
    { role: "user", content: "Repeated prompt", createdAt: 3, branchPoint: { kind: "codex", beforeTurnId: "t2", previousTurnId: "t1" } },
    { role: "assistant", content: "Original later answer", createdAt: 4 },
    { role: "user", content: "Repeated prompt", createdAt: 5, branchPoint: { kind: "codex", beforeTurnId: "t3", previousTurnId: "t2" } },
    { role: "assistant", content: "Further context must stay out", createdAt: 6 },
  ];
  const transcripts = new Map([["parent", originals]]);
  const source: ImportSource = { provider: "codex", discover: async () => ({ chats: [chat] }),
    read: async (value) => transcripts.get(value.sourceId)! };
  const service = new NativeHistoryService(index, legacy, [source]);
  try {
    const id = index.cache(chat, originals).conversation.id;
    const original = index.get(id)!;
    const selected = original.messages[2]!;
    const frame = await NativeRunContext.prepare(service, legacy, { type: "chat", text: "Edited", agent: "codex",
      conversationId: id, branchFrom: { messageId: selected.id, promptHash: promptFingerprint(selected.content) } }, "codex", "branch-run");
    expect(frame.resumeSessionID).toBe("parent");
    expect(frame.forkPoint).toEqual({ kind: "codex", beforeTurnId: "t2", previousTurnId: "t1" });
    expect(frame.contextMessages).toEqual([]);
    expect(() => frame.bind({ id: "parent" })).toThrow("independent branch");
    frame.bind({ id: "child", workspacePath: dir });
    frame.cacheResponse("New answer");
    const childID = frame.conversation.id;
    expect(index.get(id)).toEqual(original);
    expect(index.messages(childID).map((message) => message.content)).toEqual(["First", "First answer", "Edited", "New answer"]);
    expect(index.branches.family(childID).map((branch) => branch.id)).toEqual([id, childID]);
    expect(index.branches.family(childID)[1]!.messageNumber).toBe(2);
    const mirrored = index.messages(childID).map((message) => ({ ...message, createdAt: message.created_at }));
    transcripts.set("child", mirrored);
    await frame.release();
    index.cache(chat, originals);
    expect(index.branches.family(childID)).toHaveLength(2);
    index.close(); index = new NativeHistoryIndex(path);
    expect(index.branches.family(childID)[0]!.id).toBe(id);
    expect(index.messages(id)[2]!.branchPoint?.kind).toBe("codex");
    expect(index.branchState(id).messages[1]!.canBranch).toBe(true);
    const stale = { type: "chat" as const, text: "Edited", conversationId: id,
      branchFrom: { messageId: selected.id, promptHash: promptFingerprint("changed prompt") } };
    const reopened = new NativeHistoryService(index, legacy, [source]);
    await expect(NativeRunContext.prepare(reopened, legacy, stale, "codex", "stale")).rejects.toThrow("message changed");
    expect(index.branches.family(id)).toHaveLength(2);
    reopened.stop();
  } finally { service.stop(); index.close(); await rm(dir, { recursive: true, force: true }); }
});

test("Claude history retains the preceding assistant boundary and restores the first prompt into a fresh session", () => {
  const rows = [
    { type: "user", uuid: "u1", message: { content: "One" } },
    { type: "assistant", uuid: "a1", parentUuid: "u1", message: { content: "Answer one" } },
    { type: "user", uuid: "u2", parentUuid: "a1", message: { content: "Two" } },
    { type: "assistant", uuid: "a2", parentUuid: "u2", message: { content: "Answer two" } },
  ];
  const messages = claudeMessages(rows.map((row) => JSON.stringify(row)).join("\n"), 1);
  expect(messages[0]!.branchPoint).toEqual({ kind: "start" });
  expect(messages[2]!.branchPoint).toEqual({ kind: "claude", resumeSessionAt: "a1" });
  const args = buildClaudeArgs("Revised", { type: "chat", text: "Revised", providerSessionId: "parent",
    providerFork: messages[2]!.branchPoint });
  expect(args.slice(args.indexOf("--resume"), args.indexOf("--resume") + 2)).toEqual(["--resume", "parent"]);
  expect(args).toContain("--fork-session");
  expect(args.slice(args.indexOf("--resume-session-at") + 1)[0]).toBe("a1");
});

for (const mode of ["fork", "fork-empty"]) {
  test(`Codex ${mode} uses a separate native session and verifies the exact earlier history before sending`, async () => {
    await withFixture(mode, async ({ adapter, workspace, log }) => {
      const sessions: string[] = [];
      const result = await adapter.run({ type: "chat", text: "Edited", workspacePath: workspace,
        providerSessionId: "imported-thread", providerFork: { kind: "codex", beforeTurnId: "turn-replaced",
          ...(mode === "fork" ? { previousTurnId: "turn-ancestor" } : {}) } }, {
        onActivity() {}, onChunk() {}, onSession(session) { sessions.push(session.id); },
      }).finished;
      const rpc = (await Bun.file(log).text()).trim().split("\n").map((line) => JSON.parse(line));
      expect(result.text).toBe("Independent branch reply");
      expect(sessions).toEqual(["fork-test"]);
      expect(rpc.find((message) => message.method === "turn/start").params.threadId).toBe("fork-test");
      expect(rpc.find((message) => message.method === "thread/resume")).toBeUndefined();
    });
  });
}

test("an agent that ignores the requested fork boundary cannot receive the edited prompt", async () => {
  await withFixture("fork-invalid", async ({ adapter, workspace, log, marker }) => {
    await expect(adapter.run({ type: "chat", text: "Edited", workspacePath: workspace,
      providerSessionId: "imported-thread", providerFork: { kind: "codex", beforeTurnId: "turn-replaced", previousTurnId: "turn-ancestor" } },
    { onActivity() {}, onChunk() {} }).finished).rejects.toThrow("could not fork");
    const rpc = await Bun.file(log).text();
    expect(rpc).not.toContain('"method":"turn/start"');
    expect(await Bun.file(marker).text()).toBe("archived");
  });
});
