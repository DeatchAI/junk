import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SqliteHistory } from "../history/SqliteHistory";
import { NativeHistoryIndex } from "../history/native/NativeHistoryIndex";
import { NativeHistoryService } from "../history/native/NativeHistoryService";
import { NativeRunContext } from "../history/native/NativeRunContext";
import { nativeSourceKey } from "../history/native/NativeIdentity";
import { claudeMessages } from "../imports/ClaudeImportSource";
import type { ExternalChat, ImportedMessage, ImportSource } from "../imports/ImportTypes";
import { withFixture } from "../agents/codex/fixtures/CodexFixtureHarness";
import { promptFingerprint, responseBranchPoint } from "./BranchTypes";

for (const provider of ["codex", "claude"] as const) {
  for (const selectedTurn of [0, 2]) {
    test(`${provider} branches after reply ${selectedTurn + 1}, retaining the reply and excluding later turns`, async () => {
      const dir = await mkdtemp(join(tmpdir(), "detach-reply-branch-"));
      const index = new NativeHistoryIndex(join(dir, "index.sqlite"));
      const legacy = new SqliteHistory(join(dir, "legacy.sqlite"));
      const chat: ExternalChat = { provider, sourceId: "parent", sourceKey: nativeSourceKey(provider, "parent"),
        title: "Original", workspacePath: dir, canResume: true, createdAt: 1, updatedAt: 2 };
      const messages: ImportedMessage[] = provider === "codex" ? [0, 1, 2].flatMap(i => [
        { role: "user" as const, content: `Question ${i}`, createdAt: i * 2 + 1,
          branchPoint: { kind: "codex" as const, beforeTurnId: `t${i}`, previousTurnId: i ? `t${i - 1}` : undefined } },
        { role: "assistant" as const, content: `Answer ${i}`, createdAt: i * 2 + 2 },
      ]) : claudeMessages([0, 1, 2].flatMap(i => [
        { type: "user", uuid: `u${i}`, parentUuid: i ? `a${i - 1}` : undefined, message: { content: `Question ${i}` } },
        { type: "assistant", uuid: `a${i}`, parentUuid: `u${i}`, message: { content: `Answer ${i}` } },
      ]).map(row => JSON.stringify(row)).join("\n"), 1);
      const source: ImportSource = { provider, discover: async () => ({ chats: [chat] }), read: async () => messages };
      const service = new NativeHistoryService(index, legacy, [source]);
      try {
        const id = index.cache(chat, messages).conversation.id;
        const original = index.get(id)!;
        const selected = original.messages[selectedTurn * 2]!;
        expect(index.branchState(id).messages[selectedTurn]!.canBranchAfter).toBe(true);
        const frame = await NativeRunContext.prepare(service, legacy, { type: "chat", text: "New direction", agent: provider,
          conversationId: id, branchFrom: { messageId: selected.id, promptHash: promptFingerprint(selected.content), afterResponse: true } },
          provider, "reply-branch");
        expect(frame.forkPoint).toEqual(provider === "codex"
          ? { kind: "codex", beforeTurnId: selectedTurn === 2 ? undefined : "t1", previousTurnId: `t${selectedTurn}` }
          : { kind: "claude", resumeSessionAt: `a${selectedTurn}` });
        frame.bind({ id: "child", workspacePath: dir });
        frame.cacheResponse("New response");
        expect(index.messages(frame.conversation.id).map(message => message.content)).toEqual([
          ...messages.slice(0, (selectedTurn + 1) * 2).map(message => message.content), "New direction", "New response",
        ]);
        expect(index.get(id)).toEqual(original);
      } finally { service.stop(); index.close(); await rm(dir, { recursive: true, force: true }); }
    });
  }
}

test("Claude branches after the final part of a multi-part assistant reply", () => {
  const messages = claudeMessages([
    { type: "user", uuid: "u1", message: { content: "Question" } },
    { type: "assistant", uuid: "a1", parentUuid: "u1", message: { content: "Progress" } },
    { type: "assistant", uuid: "a2", parentUuid: "a1", message: { content: "Final reply" } },
  ].map(row => JSON.stringify(row)).join("\n"), 1);
  expect(messages).toHaveLength(2);
  expect(responseBranchPoint(messages, 0)).toEqual({ kind: "claude", resumeSessionAt: "a2" });
});

test("an unfinished reply has no after-response branch point", () => {
  expect(responseBranchPoint([{ role: "user", branchPoint: { kind: "codex", beforeTurnId: "t1" } }], 0)).toBeUndefined();
});

test("Codex forks the latest completed reply and verifies its tail before sending the follow-up", async () => {
  await withFixture("fork-after", async ({ adapter, workspace, log }) => {
    const result = await adapter.run({ type: "chat", text: "New direction", workspacePath: workspace,
      providerSessionId: "imported-thread", providerFork: { kind: "codex", previousTurnId: "turn-selected" } },
      { onActivity() {}, onChunk() {} }).finished;
    const calls = (await Bun.file(log).text()).trim().split("\n").map(line => JSON.parse(line));
    expect(result.text).toBe("Independent branch reply");
    expect(calls.find(call => call.method === "thread/fork").params.beforeTurnId).toBeUndefined();
    expect(calls.find(call => call.method === "turn/start").params.threadId).toBe("fork-test");
    expect(calls.some(call => call.method === "thread/resume")).toBe(false);
  });
});
