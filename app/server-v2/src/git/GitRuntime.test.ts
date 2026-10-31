import { expect, test } from "bun:test";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { git } from "./GitRepository";

test("native task lifecycle captures real Git changes before done and exposes authenticated discard/Undo", async () => {
  const base = mkdtempSync(join(tmpdir(), "detach-git-runtime-")), workspace = join(base, "project"), data = join(base, "data");
  mkdirSync(workspace); mkdirSync(data);
  await git(workspace, ["init", "-b", "main"]); await git(workspace, ["config", "user.name", "Fixture"]);
  await git(workspace, ["config", "user.email", "fixture@example.invalid"]);
  writeFileSync(join(workspace, "file.txt"), "committed\n");
  await git(workspace, ["add", "."]); await git(workspace, ["commit", "-m", "Fixture"]);
  writeFileSync(join(workspace, "file.txt"), "user edit\n");
  const executable = join(base, "claude");
  writeFileSync(executable, `#!${process.execPath}
if (process.argv.includes('-p')) {
  await Bun.write('file.txt', ['user edit', 'agent edit', ''].join(String.fromCharCode(10)));
  await import(${JSON.stringify(join(import.meta.dir, "../imports/fixtures/ResumeClaudeCLI.ts"))});
} else console.log('fixture');
`);
  chmodSync(executable, 0o755);
  const probe = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: () => new Response() });
  const port = probe.port; await probe.stop(true);
  const token = crypto.randomUUID(), headers = { authorization: `Bearer ${token}` };
  const child = Bun.spawn([process.execPath, "src/index.ts"], { cwd: join(import.meta.dir, "../.."), env: {
    ...process.env, PATH: `${base}:${process.env.PATH}`, PORT: String(port), DETACH_RUNTIME_TOKEN: token, DETACH_DATA_DIR: data, DETACH_DATABASE_PATH: join(data, "chats.sqlite"),
    DETACH_CLAUDE_PATH: executable, CLAUDE_CONFIG_DIR: join(base, "claude-config"), NODE_ENV: "test", DETACH_NATIVE_HISTORY_AUTO_SYNC: "0",
  }, stdout: "ignore", stderr: "pipe" });
  let socket: WebSocket | undefined;
  const url = (route: string) => `http://127.0.0.1:${port}/api/git/${route}`;
  try {
    let ready = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      try { if ((await fetch(url("settings"), { headers })).ok) { ready = true; break; } } catch {}
      if (child.exitCode !== null) throw new Error(await new Response(child.stderr).text());
      await Bun.sleep(40);
    }
    expect(ready).toBe(true);
    expect((await fetch(url("settings"))).status).toBe(401);
    expect((await fetch(url("settings"), { headers: { ...headers, Origin: "https://example.invalid" } })).status).toBe(403);
    socket = new WebSocket(`ws://127.0.0.1:${port}/?token=${token}`);
    await new Promise<void>((resolve, reject) => { socket!.onopen = () => resolve(); socket!.onerror = () => reject(new Error("Socket failed")); });
    const done = new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("Task did not complete")), 10_000);
      socket!.addEventListener("message", event => {
        const message = JSON.parse(String(event.data));
        if (message.type === "error") { clearTimeout(timer); reject(new Error(message.error)); }
        if (message.type === "done") { clearTimeout(timer); resolve(message); }
      });
    });
    socket.send(JSON.stringify({ type: "chat", text: "Make the fixture edit", displayText: "Make the fixture edit", agent: "claude", runId: "git-native", workspacePath: workspace, mcpServerIds: [] }));
    const completion = await done;
    const query = `workspace=${encodeURIComponent(workspace)}&conversation=${completion.conversationId}`;
    const tasks = await (await fetch(url(`tasks?${query}`), { headers })).json() as any;
    expect(tasks.tasks[0].runId).toBe("git-native"); expect(tasks.tasks[0].files[0].additions).toBe(1);
    expect(tasks.tasks[0].messageOrdinal).toBe(0);
    const call = async (route: string, body: object) => {
      const response = await fetch(url(route), { method: "POST", headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify(body) });
      const result = await response.json() as any; expect(response.status).toBe(200); return result;
    };
    const preview = await call("preview", { workspace, run: "git-native" });
    await call("apply", { plan: preview.id }); expect(readFileSync(join(workspace, "file.txt"), "utf8")).toBe("user edit\n");
    const undo = await call("preview", { workspace, run: "git-native", undo: true });
    await call("apply", { plan: undo.id }); expect(readFileSync(join(workspace, "file.txt"), "utf8")).toBe("user edit\nagent edit\n");
  } finally { socket?.close(); child.kill(); await child.exited; rmSync(base, { recursive: true, force: true }); }
}, 20_000);
