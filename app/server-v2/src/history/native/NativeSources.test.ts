import { expect, test } from "bun:test";
import { chmod, mkdir, mkdtemp, rm, symlink } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { FileSessionSource, treeSessionMessages } from "./FileSessionSource";
import { ACPHistorySource } from "./ACPHistorySource";
import { AmpHistorySource } from "./AmpHistorySource";

test("Pi and Omp histories preserve branch/title metadata, redact reasoning and reject unsafe paths", async () => {
  const root = await mkdtemp(join(tmpdir(), "detach-tree-history-"));
  const data = [
    { type: "title", title: "Provider session name" },
    { type: "session", id: "session-tree", cwd: root, timestamp: "2026-09-01T00:00:00Z" },
    { type: "message", id: "u1", parentId: null, message: { role: "user", content: "Original task" } },
    { type: "message", id: "bad-branch", parentId: "u1", message: { role: "assistant", content: "Abandoned answer" } },
    { type: "message", id: "a1", parentId: "u1", message: { role: "assistant", content: [{ type: "thinking", thinking: "private reasoning" }, { type: "text", text: "Current answer" }] } },
    { type: "session_info", id: "info", parentId: "a1", name: "Pi native name" },
  ].map((entry) => JSON.stringify(entry)).join("\n") + "\n";
  try {
    const file = join(root, "session.jsonl"); await Bun.write(file, data);
    await mkdir(join(root, "project")); await symlink(file, join(root, "project", "symlink.jsonl"));
    const pi = new FileSessionSource("pi", root, async () => "fixture");
    const result = await pi.discover(); expect(result.chats).toHaveLength(1); expect(result.complete).toBe(true);
    expect(result.chats[0]?.canResume).toBe(true); expect(result.chats[0]?.title).toBe("Pi native name");
    const messages = await pi.read(result.chats[0]!);
    expect(messages.map((message) => message.content)).toEqual(["Original task", "Current answer"]);
    expect(await Bun.file(file).text()).toBe(data);
    await expect(pi.read({ ...result.chats[0]!, locator: "/etc/passwd" })).rejects.toThrow("outside");
    expect(() => treeSessionMessages("{broken}\n" + data, 1000)).toThrow("malformed");
    const omp = new FileSessionSource("omp", root, async () => "fixture", async () => false);
    const ompChat = (await omp.discover()).chats[0];
    expect(ompChat?.canResume).toBe(false); expect(ompChat?.title).toBe("Provider session name");
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("ACP discovery/replay never prompts, denies permissions and joins token chunks correctly", async () => {
  const root = await mkdtemp(join(tmpdir(), "detach-acp-history-"));
  try {
    const executable = join(root, "acp-fixture");
    const script = join(import.meta.dir, "fixtures/HistoryACPFixture.ts");
    await Bun.write(executable, `#!${process.execPath}\nawait import(${JSON.stringify(script)});\n`); await chmod(executable, 0o755);
    const source = new ACPHistorySource("fx", async () => executable);
    const result = await source.discover(); expect(result.complete).toBe(true); expect(result.chats[0]?.canResume).toBe(true);
    const messages = await source.read(result.chats[0]!);
    expect(messages[0]?.content).toBe("Saved prompt"); expect(messages[1]?.content).not.toContain("Historical test output");
    expect(messages[1]?.parts?.find((part) => part.type === "activity")?.output).toContain("Historical test output");
    expect(messages[1]?.content).toContain("Token-joined answer");
    expect(messages[1]?.content).not.toContain("Token\n\n-joined");
    const unsupported = join(root, "unsupported");
    await Bun.write(unsupported, `#!${process.execPath}\nprocess.env.HISTORY_FIXTURE_UNSUPPORTED="1"; await import(${JSON.stringify(script)});\n`); await chmod(unsupported, 0o755);
    await expect(new ACPHistorySource("grok", async () => unsupported).discover()).rejects.toThrow("does not expose session listing");
  } finally { await rm(root, { recursive: true, force: true }); }
});

test("Amp JSON interfaces are version-gated and retain native IDs and workspace", async () => {
  const calls: string[][] = [];
  const source = new AmpHistorySource(async () => "fixture", async (_executable, args) => {
    calls.push(args);
    return args[1] === "list" ? [{ id: "T-saved-1234", title: "Amp native task", cwd: tmpdir(), created: 1_780_000_000_000, updated: 1_780_000_001_000 }]
      : { messages: [{ role: "user", content: [{ type: "text", text: "Original" }] }, { role: "assistant", content: [{ type: "text", text: "Response" }] }] };
  });
  const { chats } = await source.discover(); expect(chats[0]?.sourceId).toBe("T-saved-1234"); expect(chats[0]?.canResume).toBe(true);
  expect((await source.read(chats[0]!)).map((message) => message.content)).toEqual(["Original", "Response"]);
  expect(calls).toEqual([["threads", "list", "--json"], ["threads", "export", "T-saved-1234"]]);
  const unsupported = new AmpHistorySource(async () => "fixture", async () => ({ unknown: [] }));
  await expect(unsupported.discover()).rejects.toThrow("supported JSON");
});
