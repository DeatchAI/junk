import { expect, test } from "bun:test";
import { chmod, mkdir, mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { SqliteHistory } from "../SqliteHistory";
import { promptFingerprint } from "../../branches/BranchTypes";

test("app socket automatically discovers, searches, resumes and creates provider-native sessions without copying legacy chats", async () => {
  const directory = await mkdtemp(join(tmpdir(), "detach-native-runtime-"));
  const probe = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: () => new Response() });
  const port = probe.port; await probe.stop(true);
  const token = crypto.randomUUID(); const config = join(directory, "claude-config");
  const folder = join(config, "projects", "fixture-project"); const bin = join(directory, "bin");
  await mkdir(folder, { recursive: true }); await mkdir(bin);
  const original = join(folder, "session-fixture-1234.jsonl");
  const transcript = [
    { type: "user", sessionId: "session-fixture-1234", uuid: "u", cwd: directory,
      timestamp: "2026-09-01T00:00:00Z", message: { content: "ORIGINAL_FIXTURE_PROMPT" } },
    { type: "assistant", uuid: "a", parentUuid: "u", timestamp: "2026-09-01T00:00:01Z", message: { content: [{ type: "text", text: "Nebula-search-token original reply" }] } },
    { type: "custom-title", customTitle: "Native fixture title" },
  ].map((row) => JSON.stringify(row)).join("\n") + "\n";
  await Bun.write(original, transcript);
  const executable = join(bin, "claude");
  await Bun.write(executable, `#!${process.execPath}\nawait import(${JSON.stringify(join(import.meta.dir, "../../imports/fixtures/ResumeClaudeCLI.ts"))});\n`);
  await chmod(executable, 0o755);
  const database = join(directory, "detach", "chats.sqlite");
  const legacy = new SqliteHistory(database);
  const archive = legacy.addUserMessage(undefined, "Legacy archive prompt").conversation;
  legacy.metadata.record(archive.id, "claude", directory); legacy.addAssistantMessage(archive.id, "Legacy archive answer");
  const snapshot = legacy.get(archive.id);
  const command = Bun.env.DETACH_TEST_RUNTIME_BINARY ? [Bun.env.DETACH_TEST_RUNTIME_BINARY] : [process.execPath, "src/index.ts"];
  const child = Bun.spawn(command, {
    cwd: join(import.meta.dir, "../../.."), env: { ...process.env, PATH: `${bin}:${process.env.PATH}`,
      PORT: String(port), DETACH_RUNTIME_TOKEN: token, DETACH_DATA_DIR: join(directory, "detach"), DETACH_DATABASE_PATH: database,
      CLAUDE_CONFIG_DIR: config, DETACH_CLAUDE_PATH: executable, DETACH_HISTORY_PROVIDERS: "claude", DETACH_NATIVE_HISTORY_AUTO_SYNC: "1", NODE_ENV: "test" },
    stdout: "ignore", stderr: "pipe",
  });
  let socket: WebSocket | undefined;
  const events: any[] = [];
  try {
    let ready = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      try { ready = (await fetch(`http://127.0.0.1:${port}`, { headers: { authorization: `Bearer ${token}` } })).ok; if (ready) break; } catch {}
      if (child.exitCode !== null) throw new Error(await new Response(child.stderr).text());
      await Bun.sleep(50);
    }
    expect(ready).toBe(true);
    socket = new WebSocket(`ws://127.0.0.1:${port}/?token=${token}`);
    socket.addEventListener("message", (event) => events.push(JSON.parse(String(event.data))));
    await new Promise<void>((resolve, reject) => { socket!.onopen = () => resolve(); socket!.onerror = () => reject(new Error("Socket failed")); });
    const request = (message: object, type: string) => new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => { socket!.removeEventListener("message", receive); reject(new Error(`Missing ${type}: ${JSON.stringify(events.slice(-4))}`)); }, 10_000);
      const receive = (event: MessageEvent) => {
        const response = JSON.parse(String(event.data)); if (response.type !== type) return;
        clearTimeout(timer); socket!.removeEventListener("message", receive); resolve(response);
      };
      socket!.addEventListener("message", receive); socket!.send(JSON.stringify(message));
    });
    const waitList = async (predicate: (list: any[]) => boolean) => {
      for (let i = 0; i < 100; i++) {
        const { conversations } = await request({ type: "list_conversations" }, "conversations_list");
        if (predicate(conversations)) return conversations;
        await Bun.sleep(30);
      }
      throw new Error("History did not converge");
    };
    const list = await waitList((list) => list.some((chat) => chat.origin === "provider"));
    const conversation = list.find((chat: any) => chat.origin === "provider");
    expect(conversation.title).toBe("Native fixture title"); expect(conversation.canResume).toBe(true);
    expect(list.find((chat: any) => chat.id === archive.id)?.origin).toBe("legacy");
    const loaded = await request({ type: "get_conversation", conversationId: conversation.id }, "conversation");
    expect(loaded.messages).toHaveLength(2); expect(await Bun.file(original).text()).toBe(transcript);
    const search = await request({ type: "search_conversations", query: "Nebula-search-token", requestId: "search" }, "history_search_results");
    expect(search.conversations[0].id).toBe(conversation.id); expect(search.conversations[0].searchSnippet).toContain("Nebula");
    const done = await request({ type: "chat", runId: "native-resume", text: "Continue the original task", conversationId: conversation.id,
      agent: "claude", providerSessionId: "forged-must-be-discarded", mcpServerIds: [] }, "done");
    expect(done.conversationId).toBe(conversation.id);
    expect(events.some((event) => event.type === "provider_session" && event.runId === "native-resume" && event.conversation.id === conversation.id)).toBe(true);
    expect((await Bun.file(original).text()).startsWith(transcript)).toBe(true);
    expect((await request({ type: "get_conversation", conversationId: conversation.id }, "conversation")).messages.at(-1).content).toBe("Native session continued");
    const savedBefore = await Bun.file(original).text();
    await request({ type: "edit_message", messageId: loaded.messages[0].id, content: "must not mutate" }, "history_error");
    expect(await Bun.file(original).text()).toBe(savedBefore);
    const fresh = await request({ type: "chat", runId: "native-new", text: "A brand new task", agent: "claude", workspacePath: directory, mcpServerIds: [] }, "done");
    expect(fresh.conversationId.startsWith("native_")).toBe(true); expect(fresh.conversationId).not.toBe(conversation.id);
    expect((await readdir(folder)).filter((name) => name.startsWith("fixture-new-")).length).toBe(1);
    await request({ type: "chat", runId: "legacy-continue", text: "Continue archive", agent: "claude", conversationId: archive.id, mcpServerIds: [] }, "done");
    expect(legacy.list()).toHaveLength(1); expect(legacy.get(archive.id)).toEqual(snapshot);
    await Bun.write(original, savedBefore + JSON.stringify({ type: "custom-title", customTitle: "Renamed in Claude" }) + "\n");
    await request({ type: "refresh_provider_history" }, "provider_history_status");
    await waitList((list) => list.some((chat) => chat.id === conversation.id && chat.title === "Renamed in Claude"));
    await request({ type: "delete_conversation", conversationId: conversation.id }, "deleted");
    expect((await request({ type: "list_conversations" }, "conversations_list")).conversations.some((chat: any) => chat.id === conversation.id)).toBe(false);
    expect(await Bun.file(original).exists()).toBe(true);
    await request({ type: "restore_hidden_history" }, "conversations_list");
    await waitList((list) => list.some((chat) => chat.id === conversation.id));
    expect(legacy.get(archive.id)).toEqual(snapshot);
    expect(events.filter((event) => event.type === "error")).toEqual([]);
    const failure = await request({ type: "chat", runId: "missing-ack", text: "NO_SAVED_SESSION_ACK", agent: "claude", workspacePath: directory, mcpServerIds: [] }, "error");
    expect(failure.error).toContain("did not acknowledge a saved session");
    expect(events.filter((event) => event.type === "activity").some((event) => event.conversationId?.startsWith("pending_"))).toBe(false);
    expect(legacy.list()).toHaveLength(1);

    // Bulk native history must not share the live socket's message-size limit.
    const largeAnswer = "Complete Unicode saved answer 🙂\n".repeat(80_000);
    const lastNativeMessage = JSON.parse(savedBefore.trim().split("\n").at(-1)!);
    const largeTranscript = savedBefore + JSON.stringify({ type: "assistant", uuid: "large-answer",
      parentUuid: lastNativeMessage.uuid,
      timestamp: "2026-09-01T00:00:03Z", message: { content: [{ type: "text", text: largeAnswer }] } }) + "\n";
    await Bun.write(original, largeTranscript);
    const historyURL = `http://127.0.0.1:${port}/api/history/conversation?id=${encodeURIComponent(conversation.id)}`;
    expect((await fetch(historyURL)).status).toBe(401);
    const response = await fetch(historyURL, { headers: { authorization: `Bearer ${token}` } });
    expect(response.status).toBe(200); expect(response.headers.get("cache-control")).toBe("no-store");
    const httpHistory = await response.json() as any;
    expect(httpHistory.conversation.id).toBe(conversation.id);
    expect(httpHistory.messages.at(-1).content).toContain(largeAnswer.trim());
    expect(await Bun.file(original).text()).toBe(largeTranscript);
    expect((await request({ type: "ping" }, "pong")).type).toBe("pong");

    // Real socket routing into an isolated provider CLI: edit a middle prompt without appending to the parent.
    const beforeBranch = await request({ type: "get_conversation", conversationId: conversation.id }, "conversation");
    const selected = beforeBranch.messages.find((message: any) => message.role === "user" && message.content === "Continue the original task");
    expect(selected.branchPoint).toEqual({ kind: "claude", resumeSessionAt: "a" });
    const branched = await request({ type: "chat", runId: "native-branch", text: "An alternative continuation",
      agent: "claude", conversationId: conversation.id, branchFrom: { messageId: selected.id,
        promptHash: promptFingerprint(selected.content) }, mcpServerIds: [],
      providerFork: { kind: "claude", resumeSessionAt: "forged-client-boundary" } }, "done");
    expect(branched.conversationId).not.toBe(conversation.id);
    expect(await Bun.file(original).text()).toBe(largeTranscript);
    const alternate = await request({ type: "get_conversation", conversationId: branched.conversationId }, "conversation");
    expect(alternate.messages.map((message: any) => message.content)).toEqual([
      "ORIGINAL_FIXTURE_PROMPT", "Nebula-search-token original reply", "An alternative continuation", "Native branch continued",
    ]);
    const branches = await request({ type: "get_conversation_branches", conversationId: branched.conversationId }, "conversation_branch_state");
    expect(branches.branches.map((branch: any) => branch.id)).toEqual([conversation.id, branched.conversationId]);
    expect(branches.branches[1].messageNumber).toBe(2);
    const first = alternate.messages[0];
    const nested = await request({ type: "chat", runId: "first-message-branch", text: "A fresh first prompt",
      agent: "claude", conversationId: branched.conversationId,
      branchFrom: { messageId: first.id, promptHash: promptFingerprint(first.content) }, mcpServerIds: [] }, "done");
    const nestedHistory = await request({ type: "get_conversation", conversationId: nested.conversationId }, "conversation");
    expect(nestedHistory.messages.map((message: any) => message.content)).toEqual(["A fresh first prompt", "New native session saved"]);
    const family = await request({ type: "get_conversation_branches", conversationId: nested.conversationId }, "conversation_branch_state");
    expect(family.branches).toHaveLength(3);
    expect(family.branches[2].parentId).toBe(branched.conversationId);
    expect(await Bun.file(original).text()).toBe(largeTranscript);
  } finally {
    socket?.close(); child.kill(); await child.exited;
    await rm(directory, { recursive: true, force: true });
  }
}, 30_000);
