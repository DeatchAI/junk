import { describe, expect, test } from "bun:test";

import type { ChatRequest, MCPServerConfig } from "../protocol/messages";
import { buildAgentPrompt } from "./AgentPrompt";

describe("agent tool instructions", () => {
  test("teaches every adapter the same semantic macOS workflow", () => {
    const request: ChatRequest = {
      type: "chat",
      text: "Open Notes and write a sentence",
      mcpServers: [mcpServer("detach-macos-tools")],
    };

    const prompt = buildAgentPrompt(request);
    expect(prompt).toContain("Use detach_macos_* tools for native apps and the desktop");
    expect(prompt).toContain("Prefer detach_macos_snapshot followed by ref-based actions");
    expect(prompt).toContain("Secure text fields are intentionally blocked");
  });
});

function mcpServer(id: string): MCPServerConfig {
  return {
    id,
    name: "Detach macOS",
    transport: "stdio",
    command: "/tmp/detach-runtime",
    args: ["--mcp-macos-tools"],
    enabled: true,
    created_at: 0,
    updated_at: 0,
  };
}
