import { expect, test } from "bun:test";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { DEMO_TRIGGER_PROMPTS } from "./DemoScenarios";

const executable = Bun.env.DETACH_TEST_RUNTIME_BINARY;
type Frame = { type: string; id?: string; runId?: string; command?: string; text?: string;
  error?: string; questions?: Array<{ id: string }> };

test.skipIf(!executable)("built app runtime pauses and resumes both new demo scenarios over WebSocket", async () => {
  const directory = await mkdtemp(join(tmpdir(), "detach-bundled-demos-"));
  // An unexpected real-provider path must fail against a stub, never launch an installed agent.
  const stub = join(directory, "fixture-agent");
  await writeFile(stub, "#!/bin/sh\nexit 73\n");
  await chmod(stub, 0o700);
  const probe = Bun.serve({ hostname: "127.0.0.1", port: 0, fetch: () => new Response() });
  const port = probe.port!;
  await probe.stop(true);
  const token = crypto.randomUUID();
  const child = Bun.spawn([executable!], {
    env: { ...process.env, NODE_ENV: "test", PORT: String(port), DETACH_RUNTIME_TOKEN: token,
      DETACH_PI_PATH: stub, DETACH_DATA_DIR: directory, DETACH_DATABASE_PATH: join(directory, "chats.sqlite") },
    stdout: "ignore", stderr: "pipe",
  });
  const sockets: WebSocket[] = [];
  try {
    let ready = false;
    for (let i = 0; i < 100; i++) {
      try { ready = (await fetch("http://127.0.0.1:" + port,
        { headers: { authorization: "Bearer " + token } })).ok; } catch {}
      if (ready) break;
      if (child.exitCode !== null) throw new Error(await new Response(child.stderr).text());
      await Bun.sleep(40);
    }
    expect(ready).toBe(true);
    for (const id of ["approval", "clarification"] as const) {
      const ws = new WebSocket("ws://127.0.0.1:" + port + "/?token=" + token);
      sockets.push(ws);
      const frames: Frame[] = [];
      ws.addEventListener("message", (event) => frames.push(JSON.parse(String(event.data))));
      await new Promise<void>((resolve, reject) => {
        ws.onopen = () => resolve();
        ws.onerror = () => reject(new Error("Could not connect to bundled runtime"));
      });
      const runId = crypto.randomUUID();
      const next = async (type: string): Promise<Frame> => {
        for (let i = 0; i < 500; i++) {
          const error = frames.find((frame) => frame.type === "error");
          if (error) throw new Error(error.error);
          const found = frames.find((frame) => frame.type === type && frame.runId === runId);
          if (found) return found;
          await Bun.sleep(10);
        }
        throw new Error("Bundled demo did not emit " + type);
      };
      ws.send(JSON.stringify({ type: "chat", agent: "pi", runId, workspacePath: directory,
        text: DEMO_TRIGGER_PROMPTS[id], demoMode: true, mcpServerIds: [] }));
      const request = await next(id === "approval" ? "command_approval_request" : "agent_question");
      expect(frames.some((frame) => frame.type === "done" && frame.runId === runId)).toBe(false);
      if (id === "approval") {
        expect(request.command).toBe("demo.prepare_sample_report");
        ws.send(JSON.stringify({ type: "command_approval_response", requestId: request.id, approved: true }));
      } else {
        ws.send(JSON.stringify({ type: "agent_question_response", requestId: request.id, runId,
          answers: { [request.questions![0]!.id]: { answers: ["Both"] } } }));
      }
      await next("done");
      const text = frames.filter((frame) => frame.type === "chunk").map((frame) => frame.text).join("");
      expect(text).toContain(id === "approval" ? "You approved the demo report" : "Report style: Both");
      expect(text).toContain("Demo complete");
      ws.close();
    }
  } finally {
    sockets.forEach((ws) => ws.close());
    child.kill();
    await child.exited;
    await rm(directory, { recursive: true, force: true });
  }
}, 25_000);
