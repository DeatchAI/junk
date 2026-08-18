import { describe, expect, test } from "bun:test";

import type { AgentActivityEvent } from "../protocol/messages";
import {
  createDemoRun,
  DEMO_TRIGGER_PROMPTS,
  matchDemoScenario,
  normalizeDemoPrompt,
} from "./DemoScenarios";

describe("demo scenarios", () => {
  test("only matches exact prompts when the Debug client enables demo mode", () => {
    expect(matchDemoScenario(DEMO_TRIGGER_PROMPTS.developer, false)).toBeUndefined();
    expect(matchDemoScenario(DEMO_TRIGGER_PROMPTS.developer, true)?.id).toBe("developer");
    expect(matchDemoScenario(DEMO_TRIGGER_PROMPTS.coding, true)?.id).toBe("coding");
    expect(matchDemoScenario(DEMO_TRIGGER_PROMPTS.paystubs, true)?.id).toBe("paystubs");
    expect(matchDemoScenario(DEMO_TRIGGER_PROMPTS.xReplies, true)?.id).toBe("xReplies");
    expect(matchDemoScenario("Review this pull request", true)).toBeUndefined();
    expect(matchDemoScenario(`${DEMO_TRIGGER_PROMPTS.developer}!`, true)).toBeUndefined();
  });

  test("accepts the real composer tokens selected by the Debug menu walkthrough", () => {
    const composedPrompt = [
      "@checkout-review",
      "@checkout-pr.patch",
      "@checkout-payment-test.ts",
      "@ci-notes.md",
      "/code-review",
      DEMO_TRIGGER_PROMPTS.developer,
    ].join(" ");

    expect(normalizeDemoPrompt(composedPrompt)).toBe(DEMO_TRIGGER_PROMPTS.developer);
    expect(matchDemoScenario(composedPrompt, true)?.id).toBe("developer");
  });

  test("keeps credential and filesystem demos clearly non-destructive", () => {
    const reportSteps = matchDemoScenario(DEMO_TRIGGER_PROMPTS.paystubs, true)!.steps;
    const fileSteps = matchDemoScenario(DEMO_TRIGGER_PROMPTS.sales, true)!.steps;
    const reportText = reportSteps
      .filter((step): step is Extract<typeof step, { type: "chunk" }> => step.type === "chunk")
      .map((step) => step.text)
      .join("");
    const fileText = fileSteps
      .filter((step): step is Extract<typeof step, { type: "chunk" }> => step.type === "chunk")
      .map((step) => step.text)
      .join("");

    expect(reportText).toContain("did not access a real dashboard");
    expect(fileText).toContain("Nothing was moved or deleted");
  });

  test("emits structured activities and the complete scripted response", async () => {
    const scenario = matchDemoScenario(DEMO_TRIGGER_PROMPTS.research, true)!;
    const activities: Array<{ status: string; event?: AgentActivityEvent }> = [];
    const chunks: string[] = [];
    const timeline: string[] = [];
    const waits: number[] = [];
    const run = createDemoRun(scenario, "claude", {
      onActivity(status, _toolName, event) {
        activities.push({ status, event });
        timeline.push(`activity:${status}`);
      },
      onChunk(text) {
        chunks.push(text);
        timeline.push(`chunk:${text}`);
      },
    }, async (milliseconds) => {
      waits.push(milliseconds);
    });

    const result = await run.finished;

    expect(activities.length).toBeGreaterThanOrEqual(8);
    expect(activities.every(({ event }) => event?.agent === "claude" && event.details?.demo === true)).toBe(true);
    expect(chunks.length).toBeGreaterThanOrEqual(5);
    expect(waits.reduce((total, milliseconds) => total + milliseconds, 0)).toBeGreaterThanOrEqual(35_000);
    expect(timeline[0]).toContain("planning the run");
    expect(timeline[1]).toContain("I’ll check the current pricing pages");
    expect(timeline.some((entry) => entry.includes("Checking workspace memory"))).toBe(true);
    expect(timeline.some((entry) => entry.includes("Reviewing Browser access"))).toBe(true);
    expect(result.text).toBe(chunks.join(""));
    expect(result.text).toContain("Pricing snapshot");
  });
});
