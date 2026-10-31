import { describe, expect, test } from "bun:test";
import type { AgentQuestionAnswers } from "../questions/AgentQuestion";
import { createDemoRun, DEMO_TRIGGER_PROMPTS, matchDemoScenario } from "./DemoScenarios";

const immediate = async () => {};
const scenario = (id: "approval" | "clarification") => matchDemoScenario(DEMO_TRIGGER_PROMPTS[id], true)!;

describe("interactive demos", () => {
  test("remain exact, Debug-only triggers and match the native shortcut catalog", async () => {
    const native = await Bun.file(new URL("../../../lazzy/UI/FloatingWindow/Demo/DebugDemoScenario.swift", import.meta.url)).text();
    for (const id of ["approval", "clarification"] as const) {
      expect(matchDemoScenario(DEMO_TRIGGER_PROMPTS[id], false)).toBeUndefined();
      expect(matchDemoScenario("/plan " + DEMO_TRIGGER_PROMPTS[id], true)?.id).toBe(id);
      expect(matchDemoScenario(DEMO_TRIGGER_PROMPTS[id] + "!", true)).toBeUndefined();
      expect(native).toContain(DEMO_TRIGGER_PROMPTS[id]);
    }
  });

  test.each([true, false])("approval genuinely waits, then respects approved=%s", async (approved) => {
    const decision = Promise.withResolvers<boolean>();
    const prompted = Promise.withResolvers<void>();
    const chunks: string[] = [], delays: number[] = [];
    let finished = false;
    const run = createDemoRun(scenario("approval"), "codex", {
      onActivity() {},
      onChunk: (text) => { chunks.push(text); },
      onPermission(request) {
        expect(request.toolName).toBe("demo.prepare_sample_report");
        expect(request.description).toContain("no command runs");
        prompted.resolve();
        return decision.promise;
      },
    }, async (ms) => { delays.push(ms); });
    void run.finished.then(() => { finished = true; });
    await prompted.promise;
    await Bun.sleep(5);
    expect(finished).toBe(false);
    expect(chunks.join("")).not.toContain("Demo complete");
    expect(delays.reduce((sum, ms) => sum + ms, 0)).toBeLessThan(2_000);
    decision.resolve(approved);
    const result = await run.finished;
    expect(result.text).toBe(chunks.join(""));
    expect(result.text).toContain(approved ? "You approved" : "You denied");
    expect(result.text.includes("Demo complete")).toBe(approved);
  });

  test.each(["Minimal", "Detailed", "Both"])("clarification waits and echoes the actual answer: %s", async (choice) => {
    const answer = Promise.withResolvers<AgentQuestionAnswers | null>();
    const prompted = Promise.withResolvers<void>();
    const chunks: string[] = [];
    let finished = false;
    const run = createDemoRun(scenario("clarification"), "claude", {
      onActivity() {},
      onChunk: (text) => { chunks.push(text); },
      onQuestion(request) {
        expect(request.questions[0]?.options?.map((option) => option.label)).toEqual(["Minimal", "Detailed", "Both"]);
        prompted.resolve();
        return answer.promise;
      },
    }, immediate);
    void run.finished.then(() => { finished = true; });
    await prompted.promise;
    await Bun.sleep(5);
    expect(finished).toBe(false);
    answer.resolve({ "demo-report-format": { answers: [choice] } });
    const result = await run.finished;
    expect(result.text).toContain("Report style: " + choice);
    expect(result.text).toBe(chunks.join(""));
    expect(result.text).toContain("no report or files were created");
  });

  test("a dismissed clarification does not play the success ending", async () => {
    const run = createDemoRun(scenario("clarification"), "codex", {
      onActivity() {}, onChunk() {}, onQuestion: async () => null,
    }, immediate);
    const result = await run.finished;
    expect(result.text).toContain("dismissed the demo question");
    expect(result.text).not.toContain("Demo complete");
  });

  test.each(["approval", "clarification"] as const)("Stop cancels a pending %s and ignores a late answer", async (id) => {
    const prompted = Promise.withResolvers<void>();
    const permission = Promise.withResolvers<boolean>();
    const answer = Promise.withResolvers<AgentQuestionAnswers | null>();
    const chunks: string[] = [];
    const run = createDemoRun(scenario(id), "codex", {
      onActivity() {},
      onChunk: (text) => { chunks.push(text); },
      onPermission() { prompted.resolve(); return permission.promise; },
      onQuestion() { prompted.resolve(); return answer.promise; },
    }, immediate);
    const outcome = run.finished.catch((error: Error) => error.message);
    await prompted.promise;
    run.cancel();
    expect(await outcome).toBe("Demo stopped");
    const before = chunks.join("");
    permission.resolve(true);
    answer.resolve({ "demo-report-format": { answers: ["Both"] } });
    await Bun.sleep(5);
    expect(chunks.join("")).toBe(before);
  });

  test.each(["approval", "clarification"] as const)("missing native handler cannot auto-resolve %s", async (id) => {
    const run = createDemoRun(scenario(id), "codex", { onActivity() {}, onChunk() {} }, immediate);
    await expect(run.finished).rejects.toThrow("handler");
  });
});
