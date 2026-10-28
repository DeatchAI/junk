import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { withFixture } from "../agents/codex/fixtures/CodexFixtureHarness";
import { buildClaudeArgs } from "../agents/ClaudeAdapter";
import { ACPAgentProcess } from "../agents/ACPAgentProcess";

describe("imported native sessions", () => {
  test("Codex resumes the stored thread with explicitly selected supervised permissions", async () => {
    await withFixture("command", async ({ adapter, workspace, log }) => {
      let identity: string | undefined;
      const run = adapter.run({ type: "chat", text: "Continue", permissionMode: "supervised", workspacePath: workspace, providerSessionId: "imported-thread" },
        { onActivity() {}, onChunk() {}, onSession(session) { identity = session.id; }, onPermission: async () => true });
      expect((await run.finished).text).toBe("Browser connected");
      expect(identity).toBe("imported-thread");
      const calls = (await readFile(log, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
      expect(calls.some((call) => call.method === "thread/start")).toBe(false);
      const resumed = calls.find((call) => call.method === "thread/resume");
      expect(resumed.params).toMatchObject({ threadId: "imported-thread", excludeTurns: true, cwd: workspace,
        sandbox: "workspace-write", approvalPolicy: "on-request", approvalsReviewer: "user" });
      expect(resumed.params.ephemeral).toBeUndefined();
      expect(calls.find((call) => call.method === "turn/start").params.sandboxPolicy.networkAccess).toBe(false);
    });
  });

  test("Claude uses explicit native resume only for an imported binding", () => {
    const resumed = buildClaudeArgs("Continue", { type: "chat", text: "Continue", providerSessionId: "saved-session" });
    expect(resumed).toContain("--resume"); expect(resumed).toContain("saved-session");
    expect(resumed).not.toContain("--no-session-persistence");
    expect(resumed).not.toContain("--dangerously-skip-permissions");
    expect(buildClaudeArgs("New", { type: "chat", text: "New" })).not.toContain("--no-session-persistence");
  });

  test("OpenCode loads a saved session, hides replay, and rejects execution during replay", async () => {
    const chunks: string[] = []; let approvals = 0;
    const process = new ACPAgentProcess({ command: globalThis.process.execPath,
      args: [new URL("./fixtures/ResumeACP.ts", import.meta.url).pathname], cwd: import.meta.dir,
      activityAgent: "opencode", resumeSessionId: "saved-session", callbacks: {
        onActivity() {}, onChunk(chunk) { chunks.push(chunk); }, onPermission: async () => { approvals++; return true; },
      } });
    expect((await process.run("Continue")).text).toBe("New response only");
    expect(chunks.join("")).toBe("New response only"); expect(approvals).toBe(0);
  });

  test("ACP providers without saved-session support fail explicitly instead of silently starting fresh", async () => {
    const process = new ACPAgentProcess({ command: globalThis.process.execPath,
      args: [new URL("./fixtures/ResumeACP.ts", import.meta.url).pathname, "--unsupported"], cwd: import.meta.dir,
      activityAgent: "opencode", resumeSessionId: "saved-session", callbacks: { onActivity() {}, onChunk() {} } });
    await expect(process.run("Continue")).rejects.toThrow("cannot resume");
  });
});
