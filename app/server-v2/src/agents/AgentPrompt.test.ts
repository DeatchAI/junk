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

  test("loads only the generic bundled browser skill", () => {
    const request: ChatRequest = {
      type: "chat",
      text: "Log in to my Hugging Face account",
      mcpServers: [mcpServer("detach-browser-tools")],
    };

    const prompt = buildAgentPrompt(request);
    expect(prompt).toContain("# Detach Browser");
    expect(prompt).toContain("Never use macOS typing or clicks inside Chrome");
    expect(prompt).not.toContain("# Hugging Face login");
    expect(prompt).not.toContain('input[autocomplete="username"]');
  });

  test("teaches the agent to discover capabilities through the compact broker", () => {
    const request: ChatRequest = {
      type: "chat",
      text: "Inspect the page in Chrome",
      mcpServers: [mcpServer("detach-capability-tools")],
    };

    const prompt = buildAgentPrompt(request);
    expect(prompt).toContain("detach_capabilities_list");
    expect(prompt).toContain("detach_capability_describe");
    expect(prompt).toContain("detach_capability_invoke");
    expect(prompt).not.toContain("detach_browser_execute");
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
