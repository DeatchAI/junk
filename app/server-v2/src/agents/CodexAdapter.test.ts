import { describe, expect, test } from "bun:test";

import type { MCPServerConfig } from "../protocol/messages";
import { buildCodexAppServerArgs, buildCodexTurnParams, buildCodexMCPEnv, buildCodexPrompt, codexActivityFromEvent } from "./CodexAdapter";

describe("CodexAdapter MCP configuration", () => {
  test("preserves approvals for trusted built-in tool servers", () => {
    const args = buildCodexAppServerArgs([
      mcpServer({
        id: "detach-browser-tools",
        name: "Detach Browser",
        approvalPolicy: "auto-approve",
      }),
      mcpServer({
        id: "detach-macos-tools",
        name: "Detach macOS",
        args: ["--mcp-macos-tools"],
        approvalPolicy: "auto-approve",
      }),
    ]);

    expect(args).toContain(
      'mcp_servers.detach_browser_tools.default_tools_approval_mode="approve"'
    );
    expect(args).toContain(
      'mcp_servers.detach_macos_tools.default_tools_approval_mode="approve"'
    );
  });

  test("does not pre-approve user-configured MCP servers", () => {
    const args = buildCodexAppServerArgs([mcpServer({
      id: "mcp_custom",
      name: "Custom MCP",
    })]);

    expect(args.some((arg) => arg.includes("default_tools_approval_mode"))).toBe(false);
  });

  test("passes remote MCP headers through Codex env_http_headers", () => {
    const servers = [mcpServer({
      id: "composio-mcp",
      name: "Composio MCP",
      transport: "http",
      command: undefined,
      args: undefined,
      url: "https://backend.composio.dev/tool_router/test/mcp",
      headers: { "x-api-key": "secret" },
      approvalPolicy: "auto-approve",
    })];
    const args = buildCodexAppServerArgs(servers);
    const env = buildCodexMCPEnv(servers);

    expect(args).toContain('mcp_servers.composio_mcp.env_http_headers={"x-api-key"="DETACH_MCP_COMPOSIO_MCP_X_API_KEY"}');
    expect(args).toContain('mcp_servers.composio_mcp.default_tools_approval_mode="approve"');
    expect(args.join(" ")).not.toContain("secret");
    expect(env).toEqual({ DETACH_MCP_COMPOSIO_MCP_X_API_KEY: "secret" });
  });

  test("passes image attachments to Codex as real local images", () => {
    const params = buildCodexTurnParams({
      type: "chat", text: "inspect these", files: [
        { path: "/tmp/reference.png", mimeType: "image/png" },
        { path: "/tmp/notes.txt", mimeType: "text/plain" },
        { path: "/tmp/photo.jpg" },
      ],
    }, "/tmp/workspace", "thread-test", "inspect these");
    expect(params.input).toEqual([
      { type: "text", text: "inspect these", text_elements: [] },
      { type: "localImage", path: "/tmp/reference.png" },
      { type: "localImage", path: "/tmp/photo.jpg" },
    ]);
  });

  test("passes the selected model and reasoning effort through turn settings", () => {
    const params = buildCodexTurnParams({
      type: "chat", text: "hello", model: "gpt-5.6-sol", modelSettings: { reasoningEffort: "xhigh" },
    }, "/tmp/workspace", "thread-test", "hello");
    expect(params.model).toBe("gpt-5.6-sol");
    expect(params.effort).toBe("xhigh");
  });

  test("does not paste account or tool tutorials into a Composio user turn", () => {
    const prompt = buildCodexPrompt({
      type: "chat",
      text: "list unread emails",
      mcpServers: [mcpServer({
        id: "composio-mcp",
        name: "Composio MCP",
        transport: "http",
        command: undefined,
        args: undefined,
        url: "https://backend.composio.dev/tool_router/test/mcp",
        headers: { "x-api-key": "secret" },
        approvalPolicy: "auto-approve",
        toolNames: ["composio-direct-tools-v1", "composio-toolkit:gmail"],
      })],
    });

    expect(prompt).toBe("list unread emails");
  });
});

describe("CodexAdapter activity contract", () => {
  test("keeps lifecycle events structured but not user-facing", () => {
    expect(codexActivityFromEvent({ type: "turn.started" })).toMatchObject({
      agent: "codex",
      kind: "lifecycle",
      phase: "started",
      userFacing: false,
    });
  });

  test("maps command execution starts into terminal activity", () => {
    expect(codexActivityFromEvent({
      type: "item.started",
      item: {
        id: "item_1",
        type: "command_execution",
        command: "/bin/zsh -lc \"sed -n '1,20p' server-v2/src/agents/CodexAdapter.ts\"",
        aggregated_output: "",
        exit_code: null,
        status: "in_progress",
      },
    })).toMatchObject({
      id: "item_1",
      agent: "codex",
      kind: "command",
      phase: "started",
      title: "Reading agents/CodexAdapter.ts (1,20p)",
      toolName: "terminal",
      userFacing: true,
    });
  });

  test("keeps failed command details without inventing a turn failure", () => {
    expect(codexActivityFromEvent({
      type: "item.completed",
      item: {
        id: "item_1",
        type: "command_execution",
        command: "/bin/zsh -lc 'ls /definitely_missing_codex_contract_file'",
        aggregated_output: "No such file or directory\n",
        exit_code: 1,
        status: "failed",
      },
    })).toMatchObject({
      kind: "command",
      phase: "failed",
      subtitle: "Exited with code 1",
      details: {
        exitCode: 1,
        status: "failed",
      },
    });
  });

  test("maps file changes from Codex apply-patch events", () => {
    expect(codexActivityFromEvent({
      type: "item.started",
      item: {
        id: "item_2",
        type: "file_change",
        changes: [{ path: "/tmp/example/codex_contract_probe.txt", kind: "add" }],
        status: "in_progress",
      },
    })).toMatchObject({
      kind: "file_change",
      phase: "started",
      title: "Creating example/codex_contract_probe.txt",
      toolName: "file",
      userFacing: true,
    });
  });

  test("maps MCP tool calls into named activity instead of generic Codex state", () => {
    expect(codexActivityFromEvent({
      type: "item.started",
      item: {
        id: "item_3",
        type: "mcp_tool_call",
        server: "detach_browser_tools",
        tool: "detach_browser_status",
        arguments: {},
        result: null,
        error: null,
        status: "in_progress",
      },
    })).toMatchObject({
      kind: "mcp_tool",
      phase: "started",
      title: "Checking browser status",
      subtitle: "detach_browser_tools",
      toolName: "detach_browser_status",
      userFacing: true,
    });
  });

  test("tracks Codex todo list events without promoting them to chat state", () => {
    expect(codexActivityFromEvent({
      type: "item.started",
      item: {
        id: "item_4",
        type: "todo_list",
        items: [{ text: "Return the exact requested completion token", completed: true }],
      },
    })).toMatchObject({
      kind: "plan",
      title: "Planning: Return the exact requested completion token",
      userFacing: false,
    });
  });

  test("parses top-level turn failures into user-facing errors", () => {
    expect(codexActivityFromEvent({
      type: "turn.failed",
      error: {
        message: "{\"type\":\"error\",\"status\":400,\"error\":{\"message\":\"The model is not supported.\"}}",
      },
    })).toMatchObject({
      kind: "error",
      phase: "failed",
      title: "Codex failed",
      subtitle: "The model is not supported.",
      userFacing: true,
    });
  });
});

function mcpServer(overrides: Pick<MCPServerConfig, "id" | "name"> & Partial<MCPServerConfig>): MCPServerConfig {
  return {
    transport: "stdio",
    command: "/tmp/detach-runtime",
    args: ["--mcp-browser-tools"],
    enabled: true,
    created_at: 0,
    updated_at: 0,
    ...overrides,
  };
}
