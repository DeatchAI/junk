import { afterEach, describe, expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, symlink } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ClaudeImportSource, claudeMessages } from "./ClaudeImportSource";
import { OpenCodeImportSource, openCodeMessages } from "./OpenCodeImportSource";
import { CodexImportSource, codexMessage } from "./CodexImportSource";
import { readHistoryCommand } from "./ReadOnlyProcess";
import type { CodexHistoryRPC } from "./ReadOnlyProcess";

const dirs: string[] = [];
afterEach(async () => { for (const dir of dirs.splice(0)) await rm(dir, { recursive: true, force: true }); });
const line = (value: object) => JSON.stringify(value) + "\n";

describe("read-only migration sources", () => {
  test("Claude discovers custom titles, excludes subagents/symlinks, and reads only the active branch", async () => {
    const root = await mkdtemp(join(tmpdir(), "detach-claude-import-")); dirs.push(root);
    const projects = join(root, "projects"); const project = join(projects, "project"); await mkdir(project, { recursive: true });
    const path = join(project, "session-1234.jsonl");
    await Bun.write(path,
      line({ type: "user", sessionId: "session-1234", uuid: "u1", cwd: root, timestamp: "2026-10-01T00:00:00Z", message: { content: "Add a test" } }) +
      line({ type: "assistant", uuid: "a1", parentUuid: "u1", message: { model: "claude-haiku", content: [{ type: "text", text: "Wrong branch" }] } }) +
      line({ type: "system", uuid: "s1", parentUuid: "u1" }) +
      line({ type: "assistant", uuid: "a2", parentUuid: "s1", message: { model: "claude-haiku", content: [{ type: "text", text: "Right branch" }] } }) +
      line({ type: "custom-title", customTitle: "Add Regression Test" }));
    await mkdir(join(project, "subagents"));
    await Bun.write(join(project, "subagents", "agent.jsonl"), line({ type: "user", message: { content: "Hidden" } }));
    await symlink(path, join(project, "linked.jsonl"));
    const source = new ClaudeImportSource(projects, async () => "fixture"); const result = await source.discover();
    expect(result.chats).toHaveLength(1);
    expect(result.chats[0]).toMatchObject({ title: "Add Regression Test", provider: "claude", canResume: true, model: "claude-haiku" });
    expect(Number.isInteger(result.chats[0]?.updatedAt)).toBe(true);
    const before = await Bun.file(path).text();
    expect((await source.read(result.chats[0]!)).map((message) => message.content)).toEqual(["Add a test", "Right branch"]);
    expect(await Bun.file(path).text()).toBe(before);
    await expect(source.read({ ...result.chats[0]!, locator: "/etc/passwd" })).rejects.toThrow("outside");
  });

  test("Claude handles tools and images as historical content, not instructions to execute", () => {
    const input = line({ type: "user", message: { content: [{ type: "text", text: "Inspect" }, { type: "image", source: { data: "secret-base64" } }] } }) +
      line({ type: "assistant", message: { content: [{ type: "tool_use", name: "Bash", input: { command: "rm nowhere" } }] } }) +
      line({ type: "user", message: { content: [{ type: "tool_result", content: "Historical output" }] } }) +
      line({ type: "assistant", message: { content: [{ type: "thinking", thinking: "private reasoning" }, { type: "text", text: "Finished" }] } });
    const result = claudeMessages(input, 1000);
    expect(result).toHaveLength(2); expect(result[1]?.role).toBe("assistant");
    expect(result[1]?.content).toBe("Finished");
    expect(result[1]?.parts?.some((part) => part.type === "activity" && part.output === "Historical output")).toBe(true);
    expect(JSON.stringify(result)).not.toContain("secret-base64"); expect(JSON.stringify(result)).not.toContain("private reasoning");
    expect(() => claudeMessages('{bad record}\n' + input, 1000)).toThrow("malformed");
  });

  test("OpenCode uses only list/export; timestamps and native workspace survive", async () => {
    const root = await mkdtemp(join(tmpdir(), "detach-opencode-import-")); dirs.push(root);
    const calls: string[][] = [];
    const source = new OpenCodeImportSource(async () => "fixture", async (_executable, args) => {
      calls.push(args);
      if (args[0] === "session") return [{ id: "ses_fixture", title: "Refactor", directory: root, time: { created: 1_780_000_000_000, updated: 1_780_000_005_000 } }];
      return { info: { id: "ses_fixture" }, messages: [
        { info: { role: "user", time: { created: 1_780_000_000_000 } }, parts: [{ type: "text", text: "Refactor" }] },
        { info: { role: "assistant" }, parts: [{ type: "reasoning", text: "hidden" }, { type: "tool", tool: "read", state: { output: "Old code" } }, { type: "text", text: "Done" }] },
      ] };
    }, async () => true);
    const { chats } = await source.discover(); expect(chats[0]?.canResume).toBe(true);
    expect(chats[0]?.createdAt).toBe(1_780_000_000_000);
    const messages = await source.read(chats[0]!);
    expect(messages).toHaveLength(2); expect(messages[1]?.content).toBe("Done");
    expect(messages[1]?.parts?.find((part) => part.type === "activity")?.output).toBe("Old code");
    expect(JSON.stringify(messages)).not.toContain("hidden");
    expect(calls).toEqual([["session", "list", "--format", "json", "--max-count", "10000"], ["export", "ses_fixture"]]);
    await expect(readHistoryCommand("unused", ["run", "prompt"])).rejects.toThrow("Unsupported");
    expect(() => openCodeMessages({}, 1000)).toThrow("unsupported");
  });

  test("Codex paginates active/archived lists without repairing logs; legacy fallback is explicit", async () => {
    const calls: { method: string; params: any }[] = []; let closed = 0;
    const fake = { initialize: async () => {}, close: () => { closed++; }, request: async (method: string, params: any) => {
      calls.push({ method, params });
      if (method === "thread/list") return { data: params.archived ? [] : [{ id: "thread1", name: "Session", cwd: tmpdir(), createdAt: 1_780_000_000, updatedAt: 1_780_000_001, status: { type: "notLoaded" } }], nextCursor: null };
      if (method === "thread/turns/list") throw new Error("legacy history not supported");
      if (method === "thread/read") return { thread: { turns: [{ items: [{ type: "userMessage", content: [{ type: "text", text: "Hello" }] }, { type: "agentMessage", text: "Hi" }] }] } };
      throw new Error("Unexpected method");
    } } as unknown as CodexHistoryRPC;
    const source = new CodexImportSource(async () => fake);
    const { chats } = await source.discover(); expect(chats[0]?.createdAt).toBe(1_780_000_000_000);
    expect(calls.filter((call) => call.method === "thread/list").every((call) => call.params.useStateDbOnly === true)).toBe(true);
    expect((await source.read(chats[0]!)).map((message) => message.content)).toEqual(["Hello", "Hi"]);
    expect(calls.some((call) => /start|resume|fork/.test(call.method))).toBe(false); expect(closed).toBe(2);
    expect(codexMessage({ type: "reasoning", content: ["private"] }, 1000)).toBeUndefined();
  });
});
