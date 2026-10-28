import { expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { codexMessage } from "./CodexImportSource";
import { claudeMessages } from "./ClaudeImportSource";
import { openCodeMessages } from "./OpenCodeImportSource";
import { normalizeMessages } from "./Transcript";
import { treeSessionMessages } from "../history/native/FileSessionSource";
import { NativeHistoryIndex } from "../history/native/NativeHistoryIndex";
import { nativeSourceKey } from "../history/native/NativeIdentity";
import { ResponseTranscript } from "../activity/ResponseTranscript";
import { ProviderToolActivity } from "../activity/ProviderToolActivity";
import { normalizeAgentActivity } from "../activity/ActivityNormalizer";
import type { AgentKind } from "../protocol/messages";

test("Codex keeps commentary, commands and final answer in order, with tool output outside prose", () => {
  const source = [
    { type: "agentMessage", text: "I’ll check the build." },
    { type: "commandExecution", id: "cmd", command: "/bin/zsh -lc 'xcodebuild build'", aggregatedOutput: "warning: many destinations", status: "completed" },
    { type: "fileChange", id: "edit", changes: [{ path: "app.swift", kind: "update" }] },
    { type: "agentMessage", text: "Build passed." },
  ];
  const snapshot = JSON.stringify(source);
  const [reply] = normalizeMessages(source.map((row) => codexMessage(row, 1000)!));
  expect(reply?.content).toBe("I’ll check the build.\n\nBuild passed.");
  expect(reply?.parts?.map((part) => part.type)).toEqual(["text", "activity", "activity", "text"]);
  expect(reply?.parts?.[1]).toMatchObject({ title: "Built the app", command: source[1]!.command, output: "warning: many destinations" });
  expect(JSON.stringify(source)).toBe(snapshot);
  expect(codexMessage({ type: "reasoning", text: "hidden" }, 1000)).toBeUndefined();
  expect(codexMessage({ type: "agentMessage", text: "[Command] is a literal example." }, 1000)?.content).toBe("[Command] is a literal example.");
});

test("Claude, Pi, Omp and OpenCode correlate tool results and preserve readable assistant text", () => {
  const blocks = [{ type: "text", text: "Checking." }, { type: "tool_use", id: "call", name: "Bash", input: { command: "cat example.swift" } }];
  const claude = claudeMessages([
    { type: "assistant", message: { content: blocks } },
    { type: "user", message: { content: [{ type: "tool_result", tool_use_id: "call", content: "raw code" }] } },
    { type: "assistant", message: { content: [{ type: "thinking", thinking: "hidden" }, { type: "text", text: "Done." }] } },
  ].map((value) => JSON.stringify(value)).join("\n"), 1000);
  expect(claude[0]?.content).toBe("Checking.\n\nDone.");
  expect(claude[0]?.parts?.filter((part) => part.type === "activity")).toEqual([
    expect.objectContaining({ id: "call", title: "Read files", output: "raw code" }),
  ]);
  const tree = treeSessionMessages([
    { type: "message", id: "a", message: { role: "assistant", content: blocks.map((block) => block.type === "tool_use" ? { type: "toolCall", id: "call", name: "bash", arguments: block.input } : block) } },
    { type: "message", id: "b", parentId: "a", message: { role: "toolResult", toolCallId: "call", toolName: "bash", isError: true, content: [{ type: "text", text: "command failed" }] } },
  ].map((value) => JSON.stringify(value)).join("\n"), 1000);
  expect(tree[0]?.content).toBe("Checking.");
  expect(tree[0]?.parts?.[1]).toMatchObject({ status: "failed", output: "command failed", command: "cat example.swift" });
  const open = openCodeMessages({ messages: [{ info: { role: "assistant" }, parts: [
    { type: "tool", callID: "one", tool: "read", state: { input: { filePath: "example.swift" }, output: "raw code" } },
    { type: "text", text: "Done." },
  ] }] }, 1000);
  expect(open[0]?.content).toBe("Done.");
  expect(open[0]?.parts?.[0]).toMatchObject({ type: "activity", output: "raw code" });
});

for (const provider of ["codex", "claude", "opencode", "grok", "fx", "pi", "amp", "omp"] satisfies AgentKind[]) {
  test(`${provider} live activity uses the same ledger without duplicating updated tool calls`, () => {
    const transcript = new ResponseTranscript();
    const tools = new ProviderToolActivity(provider, { onChunk: (value) => transcript.text(value),
      onActivity: (status, name, event) => transcript.activity(normalizeAgentActivity(provider, status, name, event)) });
    transcript.text("I’ll inspect the file.");
    tools.start("Bash", { command: "cat example.swift" }, "one");
    tools.finish("one", "raw code");
    transcript.text("Finished.");
    expect(transcript.parts.map((part) => part.type)).toEqual(["text", "activity", "text"]);
    expect(transcript.parts[1]).toMatchObject({ status: "completed", output: "raw code", command: "cat example.swift" });
    tools.start("Bash", { command: "sleep 10" }, "unfinished");
    transcript.finish();
    expect(transcript.parts.at(-1)?.status).toBe("finished");
  });
}

test("cache upgrades old schemas once and retains structured details offline across reopen", async () => {
  const directory = await mkdtemp(join(tmpdir(), "detach-transcript-cache-"));
  const path = join(directory, "index.sqlite");
  const old = new Database(path);
  old.exec(`CREATE TABLE provider_sessions (id TEXT PRIMARY KEY, source_key TEXT UNIQUE NOT NULL,
    provider TEXT NOT NULL, json TEXT NOT NULL, updated_at INTEGER NOT NULL, indexed_version INTEGER, unavailable INTEGER DEFAULT 0);
    CREATE TABLE provider_messages (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES provider_sessions(id) ON DELETE CASCADE,
    role TEXT NOT NULL, content TEXT NOT NULL, created_at INTEGER NOT NULL, ordinal INTEGER NOT NULL);`);
  old.close();
  let index = new NativeHistoryIndex(path);
  try {
    const chat = { provider: "codex" as const, sourceId: "fixture", sourceKey: nativeSourceKey("codex", "fixture"),
      title: "Fixture", createdAt: 1000, updatedAt: 2000, canResume: true };
    const messages = normalizeMessages([codexMessage({ type: "commandExecution", command: "echo hello", aggregatedOutput: "hello" }, 1000)!]);
    const id = index.cache(chat, messages).conversation.id;
    expect(index.needsMessages(chat)).toBe(false);
    index.close(); index = new NativeHistoryIndex(path);
    expect(index.get(id)?.messages[0]?.parts).toEqual(messages[0]?.parts);
    expect(index.get(id)?.messages[0]?.content).toBe("");
    expect(index.needsMessages(chat)).toBe(false);
  } finally { index.close(); await rm(directory, { recursive: true, force: true }); }
});
