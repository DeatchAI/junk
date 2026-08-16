import { describe, expect, test } from "bun:test";

import { buildGrokACPArgs } from "./GrokAdapter";

describe("GrokAdapter", () => {
  test("uses the dedicated ACP process instead of project MCP configuration", () => {
    expect(buildGrokACPArgs({
      type: "chat",
      text: "test",
      agent: "grok",
    })).toEqual(["agent", "--no-leader", "stdio"]);
  });

  test("passes an explicit model to the ACP process", () => {
    expect(buildGrokACPArgs({
      type: "chat",
      text: "test",
      agent: "grok",
      model: "grok-build",
    })).toEqual(["agent", "--no-leader", "--model", "grok-build", "stdio"]);
  });

  test("passes the selected reasoning effort to Grok", () => {
    expect(buildGrokACPArgs({
      type: "chat",
      text: "test",
      agent: "grok",
      model: "grok-4.5",
      modelSettings: { reasoningEffort: "high" },
    })).toEqual([
      "agent",
      "--no-leader",
      "--model",
      "grok-4.5",
      "--reasoning-effort",
      "high",
      "stdio",
    ]);
  });
});
