import { describe, expect, test } from "bun:test";

import { actionForTool, normalizeAgentActivity } from "./ActivityNormalizer";

describe("activity normalization", () => {
  test("maps concrete first-party tools to stable semantic actions", () => {
    expect(actionForTool("detach_macos_snapshot")).toBe("desktop.inspect");
    expect(actionForTool("detach_secrets_use_credential")).toBe("credential");
    expect(actionForTool("mcp__detach__search_documents")).toBe("search");
  });

  test("preserves provider detail while adding presentation semantics", () => {
    expect(normalizeAgentActivity("codex", "Reading file", "terminal", {
      id: "item-1",
      agent: "codex",
      kind: "command",
      phase: "started",
      title: "Reading FloatingChatView.swift",
      userFacing: true,
    })).toMatchObject({
      id: "item-1",
      action: "read",
      title: "Reading FloatingChatView.swift",
      phase: "started",
    });
  });

  test("creates structured events for adapters that emit only strings", () => {
    expect(normalizeAgentActivity("claude", "Testing the runtime contract", "Bash")).toMatchObject({
      agent: "claude",
      action: "test",
      kind: "command",
      phase: "started",
      userFacing: true,
    });
  });

  test("replaces generic ACP labels for known Detach tools", () => {
    expect(normalizeAgentActivity(
      "hosted",
      "Using a tool",
      "detach_macos_snapshot",
    )).toMatchObject({
      action: "desktop.inspect",
      title: "Inspecting the active Mac app",
    });
  });
});
