import { describe, expect, test } from "bun:test";

import { buildClaudeArgs } from "./ClaudeAdapter";

describe("ClaudeAdapter", () => {
  test("passes the selected effort to Claude Code for the current session", () => {
    expect(buildClaudeArgs("test", {
      type: "chat",
      text: "test",
      agent: "claude",
      model: "sonnet",
      modelSettings: { reasoningEffort: "high" },
    })).toContain("--model");
    expect(buildClaudeArgs("test", {
      type: "chat",
      text: "test",
      agent: "claude",
      model: "sonnet",
      modelSettings: { reasoningEffort: "high" },
    })).toContain("high");
  });

  test("does not add a CLI override for the automatic setting", () => {
    expect(buildClaudeArgs("test", {
      type: "chat",
      text: "test",
      agent: "claude",
      modelSettings: { reasoningEffort: "none" },
    })).not.toContain("--effort");
  });
});
