import { describe, expect, test } from "bun:test";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const detector = join(import.meta.dir, "CapabilityDetector.ts");
const runner = join(import.meta.dir, "ProcessRunner.ts");

describe("agent discovery from a macOS app environment", () => {
  test.each([
    "Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS",
    "Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS",
    "Applications/ChatGPT.app/Contents/Resources",
    ".local/bin",
  ])("discovers and launches Codex installed in %s", async (directory) => {
    const home = await mkdtemp(join(tmpdir(), "detach-cli-discovery-"));
    try {
      const executable = join(home, directory, "codex");
      await installFixture(executable, "bundled-codex");

      expect(await probe(home)).toEqual({
        executable,
        stdout: "bundled-codex",
        exitCode: 0,
      });
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });

  test("preserves the user's preferred CLI from PATH", async () => {
    const home = await mkdtemp(join(tmpdir(), "detach-cli-discovery-"));
    try {
      const preferred = join(home, "bin", "codex");
      await installFixture(preferred, "preferred-codex");
      await installFixture(
        join(home, "Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
        "bundled-codex",
      );

      expect(await probe(home, `${dirname(preferred)}:/usr/bin:/bin`)).toEqual({
        executable: preferred,
        stdout: "preferred-codex",
        exitCode: 0,
      });
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });
});

async function installFixture(path: string, version: string) {
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, `#!/bin/sh\nprintf '%s\\n' '${version}'\n`);
  await chmod(path, 0o755);
}

async function probe(home: string, path = "/usr/bin:/bin") {
  const script = `
    const { findExecutable } = await import(${JSON.stringify(detector)});
    const { runProcess } = await import(${JSON.stringify(runner)});
    const executable = await findExecutable("codex");
    const result = await runProcess({
      command: "/usr/bin/env", args: ["codex", "--version"],
    }).finished;
    console.log(JSON.stringify({ executable, stdout: result.stdout.trim(), exitCode: result.exitCode }));
  `;
  const child = Bun.spawn([process.execPath, "-e", script], {
    env: { HOME: home, PATH: path },
    stdout: "pipe",
    stderr: "pipe",
  });
  const [exitCode, stdout, stderr] = await Promise.all([
    child.exited,
    new Response(child.stdout).text(),
    new Response(child.stderr).text(),
  ]);
  if (exitCode !== 0) throw new Error(stderr || `Discovery probe exited with ${exitCode}`);
  return JSON.parse(stdout);
}
