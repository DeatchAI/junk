import { describe, expect, test } from "bun:test";

import type { MCPServerConfig } from "../protocol/messages";
import {
  autoApprovedMCPToolIdentities,
  buildACPMCPServers,
  buildClaudeAllowedTools,
  buildClaudeMCPConfig,
} from "./MCPConfig";

describe("agent-neutral MCP configuration", () => {
  test("maps one stdio server into Claude and ACP formats", () => {
    const command = "/Applications/Detach.app/Contents/Resources/detach-runtime";
    const server = mcpServer({
      id: "detach-browser-tools",
      name: "Detach Browser",
      command,
      args: ["--mcp-browser-tools"],
      env: { DETACH_RUNTIME_URL: "http://127.0.0.1:3847" },
      approvalPolicy: "auto-approve",
      toolNames: ["detach_browser_status"],
    });

    expect(buildClaudeMCPConfig([server])).toEqual({
      mcpServers: {
        detach_browser_tools: {
          command,
          args: ["--mcp-browser-tools"],
          env: { DETACH_RUNTIME_URL: "http://127.0.0.1:3847" },
        },
      },
    });
    expect(buildACPMCPServers([server])).toEqual([{
      name: "detach_browser_tools",
      command,
      args: ["--mcp-browser-tools"],
      env: [{ name: "DETACH_RUNTIME_URL", value: "http://127.0.0.1:3847" }],
    }]);
  });

  test("exposes auto-approval intent without making it provider-specific", () => {
    const trusted = mcpServer({
      id: "detach-browser-tools",
      name: "Detach Browser",
      approvalPolicy: "auto-approve",
      toolNames: ["detach_browser_status"],
    });
    const custom = mcpServer({ id: "mcp_custom", name: "Custom MCP" });

    expect(buildClaudeAllowedTools([trusted, custom])).toEqual([
      "mcp__detach_browser_tools__*",
    ]);
    expect(autoApprovedMCPToolIdentities([trusted, custom])).toEqual([
      "detach_browser_tools",
      "detach_browser_status",
    ]);
  });

  test("keeps multiple built-in tool servers agent-neutral", () => {
    const browser = mcpServer({
      id: "detach-browser-tools",
      name: "Detach Browser",
      approvalPolicy: "auto-approve",
      toolNames: ["detach_browser_status"],
    });
    const desktop = mcpServer({
      id: "detach-macos-tools",
      name: "Detach macOS",
      args: ["--mcp-macos-tools"],
      approvalPolicy: "auto-approve",
      toolNames: ["detach_macos_status", "detach_macos_snapshot"],
    });

    expect(buildClaudeAllowedTools([browser, desktop])).toEqual([
      "mcp__detach_browser_tools__*",
      "mcp__detach_macos_tools__*",
    ]);
    expect(autoApprovedMCPToolIdentities([browser, desktop])).toEqual([
      "detach_browser_tools",
      "detach_browser_status",
      "detach_macos_tools",
      "detach_macos_status",
      "detach_macos_snapshot",
    ]);
    expect(buildACPMCPServers([browser, desktop]).map((server) => server.name)).toEqual([
      "detach_browser_tools",
      "detach_macos_tools",
    ]);
  });

  test("maps remote MCP headers into ACP session configuration", () => {
    const server = mcpServer({
      id: "remote-docs",
      name: "Remote Docs",
      transport: "http",
      url: "https://example.com/mcp",
      headers: { Authorization: "Bearer token" },
    });

    expect(buildACPMCPServers([server])).toEqual([{
      type: "http",
      name: "remote_docs",
      url: "https://example.com/mcp",
      headers: [{ name: "Authorization", value: "Bearer token", secret: true }],
    }]);
  });

  test("maps Composio HTTP MCP into Grok-compatible ACP params", () => {
    const server = mcpServer({
      id: "composio-mcp",
      name: "Composio MCP",
      transport: "http",
      url: "https://backend.composio.dev/tool_router/test/mcp",
      headers: { "x-api-key": "secret" },
      approvalPolicy: "auto-approve",
    });

    expect(buildACPMCPServers([server])).toEqual([{
      type: "http",
      name: "composio_mcp",
      url: "https://backend.composio.dev/tool_router/test/mcp",
      headers: [{ name: "x-api-key", value: "secret", secret: true }],
    }]);
  });
});

function mcpServer(overrides: Pick<MCPServerConfig, "id" | "name"> & Partial<MCPServerConfig>): MCPServerConfig {
  return {
    transport: "stdio",
    command: "/tmp/detach-runtime",
    args: [],
    enabled: true,
    created_at: 0,
    updated_at: 0,
    ...overrides,
  };
}
