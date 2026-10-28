import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { withFixture } from "./fixtures/CodexFixtureHarness";
import type { AgentQuestionAnswers } from "../../questions/AgentQuestion";

describe("Codex native clarification", () => {
  test.each(["question", "question-legacy"])("keeps the turn alive and resumes it with choices and a free-text answer (%s)", async (mode) => {
    await withFixture(mode, async ({ adapter, workspace, marker, log }) => {
      const shown = Promise.withResolvers<void>();
      const answer = Promise.withResolvers<AgentQuestionAnswers | null>();
      let completed = false;
      const run = adapter.run({ type: "chat", text: "Update my project", workspacePath: workspace }, {
        onChunk() {}, onActivity() {}, onQuestion(request) {
          expect(request.questions).toHaveLength(2);
          expect(request.questions[0]?.options?.[0]?.label).toBe("Website");
          shown.resolve();
          return answer.promise;
        },
      });
      void run.finished.then(() => { completed = true; });
      try {
        await shown.promise;
        expect(completed).toBe(false);
        expect(await Bun.file(marker).exists()).toBe(false);
        answer.resolve({ project: { answers: ["Website"] }, detail: { answers: ["Add a pricing page"] } });
        expect((await run.finished).text).toBe("Updating Website: Add a pricing page");
        expect(await Bun.file(marker).exists()).toBe(true);
        const messages = (await readFile(log, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
        expect(messages.filter((item) => item.method === "turn/start")).toHaveLength(1);
        expect(messages.find((item) => item.id === "question-1").result.answers.detail.answers).toEqual(["Add a pricing page"]);
      } finally { answer.resolve(null); run.cancel(); }
    });
  });

  test("rejects questions for another task", async () => {
    await withFixture("question-foreign", async ({ adapter, workspace, marker }) => {
      let shown = false;
      const run = adapter.run({ type: "chat", text: "Update", workspacePath: workspace }, {
        onChunk() {}, onActivity() {}, async onQuestion() { shown = true; return {}; },
      });
      expect((await run.finished).text).toBe("Question cancelled");
      expect(shown).toBe(false);
      expect(await Bun.file(marker).exists()).toBe(false);
    });
  });

  test("cancels a waiting turn without executing work", async () => {
    await withFixture("question", async ({ adapter, workspace, marker }) => {
      const shown = Promise.withResolvers<void>(), answer = Promise.withResolvers<AgentQuestionAnswers | null>();
      const run = adapter.run({ type: "chat", text: "Update", workspacePath: workspace }, {
        onChunk() {}, onActivity() {}, onQuestion() { shown.resolve(); return answer.promise; },
      });
      await shown.promise;
      run.cancel();
      answer.resolve(null);
      expect((await run.finished).text).toBe("");
      expect(await Bun.file(marker).exists()).toBe(false);
    });
  });
});
