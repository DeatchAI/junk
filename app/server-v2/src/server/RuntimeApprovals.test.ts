import { expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

test("approvals wait indefinitely without consuming execution time or crossing task boundaries", async () => {
  // RuntimeContext opens local stores; isolate them from both the user's data and other tests.
  const directory = await mkdtemp(join(tmpdir(), "detach-approval-test-"));
  const child = Bun.spawn([process.execPath, join(import.meta.dir, "fixtures/RuntimeApprovalsFixture.ts")], {
    env: { ...process.env, DETACH_RUNTIME_TOKEN: "approval-fixture", NODE_ENV: "test",
      DETACH_DATA_DIR: directory, DETACH_DATABASE_PATH: join(directory, "chats.sqlite") },
    stdout: "pipe", stderr: "pipe",
  });
  try {
    const [code, stdout, stderr] = await Promise.all([
      child.exited, new Response(child.stdout).text(), new Response(child.stderr).text(),
    ]);
    if (code !== 0) throw new Error(stdout + stderr);
    expect(stdout).toContain("Indefinite approvals");
  } finally {
    child.kill();
    await rm(directory, { recursive: true, force: true });
  }
});
