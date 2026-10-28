import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DEMO_TRIGGER_PROMPTS } from "../demo/DemoScenarios";

test("chat-only runtime starts, rejects retired routes, and streams a local chat fixture", async () => {
  const directory = await mkdtemp(join(tmpdir(), "detach-chat-launch-"));
  const probe = Bun.serve({ port: 0, hostname: "127.0.0.1", fetch: () => new Response() });
  const port = probe.port;
  await probe.stop(true);
  const token = crypto.randomUUID();
  const command = Bun.env.DETACH_TEST_RUNTIME_BINARY
    ? [Bun.env.DETACH_TEST_RUNTIME_BINARY]
    : [process.execPath, "src/index.ts"];
  const child = Bun.spawn(command, {
    cwd: join(import.meta.dir, "../.."),
    env: { ...process.env, PORT: String(port), DETACH_RUNTIME_TOKEN: token,
      DETACH_DATA_DIR: directory, NODE_ENV: "test" },
    stdout: "ignore", stderr: "pipe",
  });
  let socket: WebSocket | undefined;
  try {
    const url = `http://127.0.0.1:${port}`;
    let ready = false;
    for (let attempt = 0; attempt < 80; attempt += 1) {
      try {
        const response = await fetch(url, { headers: { authorization: `Bearer ${token}` } });
        ready = response.ok;
        if (ready) break;
      } catch {}
      if (child.exitCode !== null) throw new Error(await new Response(child.stderr).text());
      await Bun.sleep(50);
    }
    expect(ready).toBe(true);
    expect((await fetch(url)).status).toBe(401);
    socket = new WebSocket(`ws://127.0.0.1:${port}/?token=${token}`);
    await new Promise<void>((resolve, reject) => {
      socket!.onopen = () => resolve();
      socket!.onerror = () => reject(new Error("Fixture socket could not connect"));
    });
    const request = (message: object, matches: (response: any) => boolean = () => true) =>
      new Promise<any>((resolve, reject) => {
        const timer = setTimeout(() => {
          socket!.removeEventListener("message", onMessage);
          reject(new Error("Timed out waiting for runtime response"));
        }, 20_000);
        const onMessage = (event: MessageEvent) => {
          const response = JSON.parse(String(event.data));
          if (!matches(response)) return;
          clearTimeout(timer);
          socket!.removeEventListener("message", onMessage);
          resolve(response);
        };
        socket!.addEventListener("message", onMessage);
        socket!.send(JSON.stringify(message));
      });
    expect((await request({ type: "ping" })).type).toBe("pong");
    for (const type of ["list_media_models", "quote_media", "generate_media", "list_quick_actions", "add_quick_action", "list_memories", "add_memory"]) {
      const response = await request({ type });
      expect(response.type).toBe("error");
      expect(response.error).toContain("does not handle");
    }
    const added = await request({ type: "add_workflow", name: "Review UI", prompt: "Review the interface." });
    expect(added.type).toBe("workflow_added");
    expect(added.workflow.kind).toBe("workflow");
    const updated = await request({ type: "update_workflow", actionId: added.workflow.id, name: "Review changes" });
    expect(updated.workflow.name).toBe("Review changes");
    expect((await request({ type: "list_workflows" })).workflows.map((item: any) => item.id)).toContain(added.workflow.id);
    expect((await request({ type: "delete_workflow", actionId: added.workflow.id })).type).toBe("workflow_deleted");
    const observed: any[] = [];
    socket.addEventListener("message", (event) => observed.push(JSON.parse(String(event.data))));
    const retired = await request({ type: "chat", agent: "hosted", text: "Do not start" });
    expect(retired.type).toBe("error");
    expect(retired.error).toContain("Unknown agent");
    const emptyHistory = await request({ type: "list_conversations" });
    expect(emptyHistory.conversations).toEqual([]);
    const chunk = await request({ type: "chat", agent: "codex", runId: crypto.randomUUID(),
      text: DEMO_TRIGGER_PROMPTS.xReplies, demoMode: true, mcpServerIds: [] },
      (response) => response.type === "chunk");
    expect(chunk.text.length).toBeGreaterThan(0);
    expect(observed.find((message) => message.type === "context_summary").contextSummary).toMatchObject({
      instructionCharacters: 0, attachmentCharacters: 0, fileCount: 0,
    });
    expect((await request({ type: "stop_stream" },
      (response) => response.type === "activity" && response.activityStatus === "Stopped")).type).toBe("activity");
  } finally {
    socket?.close();
    child.kill();
    await child.exited;
    await rm(directory, { recursive: true, force: true });
  }
}, 30_000);
