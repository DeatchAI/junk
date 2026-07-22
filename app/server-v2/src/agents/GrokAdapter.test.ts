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
});
