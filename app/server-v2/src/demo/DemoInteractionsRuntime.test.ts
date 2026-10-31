import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

test("demo decisions use production approval/question messages, responses, and Stop cleanup", async () => {
  const directory = await mkdtemp(join(tmpdir(), "detach-demo-interactions-"));
  const child = Bun.spawn([process.execPath, join(import.meta.dir, "fixtures/DemoInteractionsRuntime.ts")], {
    env: { ...process.env, NODE_ENV: "test", DETACH_RUNTIME_TOKEN: "demo-interaction-fixture",
      DETACH_DATA_DIR: directory, DETACH_DATABASE_PATH: join(directory, "chats.sqlite") },
    stdout: "pipe", stderr: "pipe",
  });
  try {
    const [code, stdout, stderr] = await Promise.all([
      child.exited, new Response(child.stdout).text(), new Response(child.stderr).text(),
    ]);
    if (code !== 0) throw new Error(stdout + stderr);
    expect(stdout).toContain("round-trip through the real runtime handlers");
  } finally {
    child.kill();
    await child.exited;
    await rm(directory, { recursive: true, force: true });
  }
}, 20_000);
