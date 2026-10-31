import { afterEach, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { readOpenCodeSessionCatalog } from "./OpenCodeSessionCatalog";
import { OpenCodeImportSource } from "./OpenCodeImportSource";

const directories: string[] = [];
afterEach(async () => { await Promise.all(directories.splice(0).map((path) => rm(path, { recursive: true, force: true }))); });

test("OpenCode discovery reads native metadata across projects without changing provider data", async () => {
  const root = await mkdtemp(join(tmpdir(), "detach-opencode-catalog-")); directories.push(root);
  const path = join(root, "opencode.db");
  const db = new Database(path);
  db.exec(`CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT, parent_id TEXT, directory TEXT, title TEXT,
    time_created INTEGER, time_updated INTEGER, time_archived INTEGER)`);
  const insert = db.prepare("INSERT INTO session VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
  insert.run("ses_global", "global", null, root, "Global", 1000, 1001, null);
  insert.run("ses_discord", "git-project", null, root, "Create Discord test server", 1000, 2000, null);
  insert.run("ses_child", "git-project", "ses_discord", root, "Agent child", 1000, 3000, null);
  insert.run("ses_archived", "other-project", null, root, "Archived", 1000, 4000, 5000);
  db.close();
  const before = await Bun.file(path).arrayBuffer();
  let commandCalls = 0;
  const source = new OpenCodeImportSource(async () => "fixture", async () => { commandCalls++; return []; },
    async () => true, () => readOpenCodeSessionCatalog(path));
  const result = await source.discover();
  expect(result.complete).toBe(true);
  expect(result.chats.map((chat) => chat.sourceId)).toEqual(["ses_archived", "ses_discord", "ses_global"]);
  expect(result.chats.find((chat) => chat.sourceId === "ses_discord")?.canResume).toBe(true);
  expect(result.chats.find((chat) => chat.sourceId === "ses_archived")?.canResume).toBe(false);
  expect(commandCalls).toBe(0);
  expect(await Bun.file(path).arrayBuffer()).toEqual(before);
});

test("project-scoped CLI fallback never claims to be an exhaustive provider catalog", async () => {
  const source = new OpenCodeImportSource(async () => "fixture", async () => [], async () => true, () => undefined);
  expect(await source.discover()).toMatchObject({ chats: [], complete: false });
  expect(readOpenCodeSessionCatalog("/no/such/opencode.db")).toBeUndefined();
});

test("OpenCode native transcript read preserves large tool history without a truncated CLI export", async () => {
  const { readOpenCodeSessionTranscript } = await import("./OpenCodeSessionCatalog");
  const { openCodeMessages } = await import("./OpenCodeImportSource");
  const root = await mkdtemp(join(tmpdir(), "detach-opencode-transcript-")); directories.push(root);
  const path = join(root, "opencode.db"); const db = new Database(path);
  db.exec(`CREATE TABLE session (id TEXT PRIMARY KEY); CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT);
    CREATE TABLE part (message_id TEXT, session_id TEXT, time_created INTEGER, id TEXT, data TEXT)`);
  db.run("INSERT INTO session VALUES (?)", ["ses_large"]);
  db.run("INSERT INTO message VALUES (?,?,?,?)", ["m1", "ses_large", 1, JSON.stringify({ role: "user", time: { created: 1 } })]);
  db.run("INSERT INTO message VALUES (?,?,?,?)", ["m2", "ses_large", 2, JSON.stringify({ role: "assistant", time: { created: 2 } })]);
  db.run("INSERT INTO part VALUES (?,?,?,?,?)", ["m1", "ses_large", 1, "p1", JSON.stringify({ type: "text", text: "Open Discord" })]);
  db.run("INSERT INTO part VALUES (?,?,?,?,?)", ["m2", "ses_large", 2, "p2", JSON.stringify({ type: "tool", tool: "observe", state: { status: "completed", output: "x".repeat(128000) } })]);
  db.run("INSERT INTO part VALUES (?,?,?,?,?)", ["m2", "ses_large", 3, "p3", JSON.stringify({ type: "text", text: "Waiting for update" })]);
  db.close();
  const messages = openCodeMessages(readOpenCodeSessionTranscript("ses_large", path), 1);
  expect(messages[0]?.content).toBe("Open Discord");
  expect(messages[1]?.content).toBe("Waiting for update");
  expect(messages[1]?.parts?.find((part) => part.type === "activity")?.output?.length).toBe(128000);
  expect(readOpenCodeSessionTranscript("ses_missing", path)).toBeUndefined();
});
