import { appendFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

// Provider-owned persistence fixture; no account, model, or network.
const args = process.argv.slice(2);
const resumed = args.includes("--resume") ? args[args.indexOf("--resume") + 1] : undefined;
const prompt = args[args.indexOf("-p") + 1]!;
if ((resumed && resumed !== "session-fixture-1234" && !resumed.startsWith("fixture-new-"))
  || args.includes("--no-session-persistence") || args.includes("--dangerously-skip-permissions")
  || (resumed && prompt.includes("ORIGINAL_FIXTURE_PROMPT"))) {
  console.error("Invalid native resume or duplicated history"); process.exit(2);
}
const fork = args.includes("--fork-session");
const id = !fork && resumed ? resumed : `fixture-new-${crypto.randomUUID()}`;
const folder = join(Bun.env.CLAUDE_CONFIG_DIR!, "projects", "fixture-project");
await mkdir(folder, { recursive: true });
const path = join(folder, `${id}.jsonl`);
let previous = await readFile(path, "utf8").catch(() => "");
if (fork) {
  const boundary = args[args.indexOf("--resume-session-at") + 1];
  const original = await readFile(join(folder, `${resumed}.jsonl`), "utf8");
  const records = original.trim().split("\n").map((line) => JSON.parse(line));
  const cut = records.findIndex((record) => record.uuid === boundary && record.type === "assistant");
  if (!resumed || cut < 0) { console.error("Invalid native fork boundary"); process.exit(2); }
  previous = records.slice(0, cut + 1).map((record) => JSON.stringify(record)).join("\n") + "\n";
  await writeFile(path, previous);
}
const parent = previous.trim().split("\n").flatMap((line) => { try { return [JSON.parse(line)]; } catch { return []; } })
  .findLast((entry) => entry.uuid)?.uuid;
const userID = crypto.randomUUID();
const answer = fork ? "Native branch continued" : resumed ? "Native session continued" : "New native session saved";
const rows = [
  { type: "user", sessionId: id, uuid: userID, parentUuid: parent, cwd: process.cwd(), timestamp: new Date().toISOString(), message: { content: prompt } },
  { type: "assistant", uuid: crypto.randomUUID(), parentUuid: userID, timestamp: new Date().toISOString(),
    message: { role: "assistant", content: [{ type: "text", text: answer }] } },
];
if (!prompt.includes("NO_SAVED_SESSION_ACK")) console.log(JSON.stringify({ type: "system", subtype: "init", session_id: id }));
await appendFile(path, rows.map((row) => JSON.stringify(row)).join("\n") + "\n");
console.log(JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text: answer }] } }));
console.log(JSON.stringify({ type: "result", result: answer }));
