import { expect, test } from "bun:test";
import { CodexAppServer } from "./CodexAppServer";
import { withFixture } from "./fixtures/CodexFixtureHarness";

for (const mode of ["fork-stalled", "startup-stalled"]) {
  test(`${mode} reports an actionable startup error instead of staying Working`, async () => {
    await withFixture(mode, async ({ executable, workspace }) => {
      const activities: string[] = [];
      const server = new CodexAppServer({ executable, cwd: workspace, startupTimeoutMs: 80,
        request: { type: "chat", text: "Hello", model: "gpt-6-luna",
          ...(mode === "fork-stalled" ? { providerSessionId: "imported-thread",
            providerFork: { kind: "codex" as const, beforeTurnId: "turn-replaced", previousTurnId: "turn-ancestor" } } : {}) },
        callbacks: { onChunk() {}, onActivity(title) { activities.push(title); } } });
      await expect(server.run("Hello")).rejects.toThrow("did not start replying");
      expect(server.isStartingTurn).toBe(false);
      expect(activities.some(title => title.includes("Waiting for Codex"))).toBe(true);
      if (mode === "fork-stalled") expect(activities).toContain("Creating a new chat branch");
    });
  });
}

test("real reasoning activity can continue beyond the startup deadline", async () => {
  await withFixture("fork-thinking", async ({ executable, workspace }) => {
    const server = new CodexAppServer({ executable, cwd: workspace, startupTimeoutMs: 50,
      request: { type: "chat", text: "Hello", providerSessionId: "imported-thread",
        providerFork: { kind: "codex", beforeTurnId: "turn-replaced", previousTurnId: "turn-ancestor" } },
      callbacks: { onChunk() {}, onActivity() {} } });
    expect(await server.run("Hello")).toEqual({ text: "Independent branch reply" });
    expect(server.isStartingTurn).toBe(false);
  });
});

test("waiting for a user answer is progress and does not trigger the startup deadline", async () => {
  await withFixture("question", async ({ executable, workspace }) => {
    const server = new CodexAppServer({ executable, cwd: workspace, startupTimeoutMs: 50,
      request: { type: "chat", text: "Hello" },
      callbacks: { onChunk() {}, onActivity() {}, async onQuestion() {
        await new Promise(resolve => setTimeout(resolve, 140));
        return { project: { answers: ["App"] }, detail: { answers: ["Compact"] } };
      } } });
    expect((await server.run("Hello")).text).toContain("Updating App");
  });
});
