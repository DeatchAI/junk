import { describe, expect, test } from "bun:test";

import {
  ACPAgentProcess,
  isAutoApprovedACPToolCall,
  selectACPPermissionOutcome,
} from "./ACPAgentProcess";
import { createTempTextFile } from "./CliAdapterUtils";

describe("ACP tool approval mapping", () => {
  test("recognizes a trusted MCP namespace in structured tool input", () => {
    expect(isAutoApprovedACPToolCall({
      title: "Calling browser tool",
      rawInput: {
        name: "detach_browser_tools__detach_browser_status",
        arguments: {},
      },
    }, ["detach_browser_tools"])).toBe(true);
  });

  test("recognizes an explicitly declared tool name", () => {
    expect(isAutoApprovedACPToolCall({
      title: "Checking browser status",
      rawInput: { tool: "detach_browser_status" },
    }, ["detach_browser_status"])).toBe(true);
  });

  test("does not trust unrelated tools", () => {
    expect(isAutoApprovedACPToolCall({
      title: "Delete a file",
      rawInput: { tool: "delete_file" },
    }, ["detach_browser_tools", "detach_browser_status"])).toBe(false);
  });

  test("selects allow or reject options supplied by the ACP agent", () => {
    const options = [
      { optionId: "yes", kind: "allow_once" },
      { optionId: "no", kind: "reject_once" },
    ];

    expect(selectACPPermissionOutcome(options, true)).toEqual({
      outcome: "selected",
      optionId: "yes",
    });
    expect(selectACPPermissionOutcome(options, false)).toEqual({
      outcome: "selected",
      optionId: "no",
    });
  });
});

describe("ACPAgentProcess", () => {
  test("sets the selected model and reasoning effort through ACP configuration", async () => {
    const fakeAgent = createTempTextFile("detach-model-acp-", "agent.ts", `
let buffer = "";
let modelSet = false;
let effortSet = false;
function send(message) { process.stdout.write(JSON.stringify(message) + "\\n"); }
for await (const chunk of Bun.stdin.stream()) {
  buffer += Buffer.from(chunk).toString("utf8");
  const lines = buffer.split(/\\r?\\n/);
  buffer = lines.pop() || "";
  for (const line of lines) {
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    if (message.method === "initialize") {
      send({ jsonrpc: "2.0", id: message.id, result: { protocolVersion: 1, agentCapabilities: {} } });
    } else if (message.method === "session/new") {
      send({
        jsonrpc: "2.0",
        id: message.id,
        result: {
          sessionId: "model-session",
          configOptions: [
            { id: "model", category: "model" },
            { id: "effort", category: "thought_level" },
          ],
        },
      });
    } else if (message.method === "session/set_config_option") {
      if (message.params.configId === "model") {
        if (message.params.value !== "opencode/deepseek-v4-flash-free") process.exit(4);
        modelSet = true;
      } else if (message.params.configId === "effort") {
        if (message.params.value !== "high") process.exit(5);
        effortSet = true;
      } else {
        process.exit(6);
      }
      send({ jsonrpc: "2.0", id: message.id, result: { configOptions: [] } });
    } else if (message.method === "session/prompt") {
      if (!modelSet || !effortSet) process.exit(7);
      send({
        jsonrpc: "2.0",
        method: "session/update",
        params: {
          sessionId: "model-session",
          update: { sessionUpdate: "agent_message_chunk", content: { type: "text", text: "OK" } }
        }
      });
      send({ jsonrpc: "2.0", id: message.id, result: { stopReason: "end_turn" } });
    }
  }
}
`);
    const agentProcess = new ACPAgentProcess({
      command: process.execPath,
      args: [fakeAgent.path],
      cwd: process.cwd(),
      model: "opencode/deepseek-v4-flash-free",
      modelSettings: { reasoningEffort: "high" },
      activityAgent: "opencode",
      callbacks: { onActivity() {}, onChunk() {} },
    });

    try {
      await expect(agentProcess.run("Reply with OK")).resolves.toEqual({ text: "OK" });
    } finally {
      fakeAgent.cleanup();
    }
  });
  test("rejects a tool turn that completes without a final assistant response", async () => {
    const fakeAgent = createTempTextFile("detach-empty-acp-", "agent.ts", `
let buffer = "";
function send(message) { process.stdout.write(JSON.stringify(message) + "\\n"); }
for await (const chunk of Bun.stdin.stream()) {
  buffer += Buffer.from(chunk).toString("utf8");
  const lines = buffer.split(/\\r?\\n/);
  buffer = lines.pop() || "";
  for (const line of lines) {
    if (!line.trim()) continue;
    const message = JSON.parse(line);
    if (message.method === "initialize") {
      send({ jsonrpc: "2.0", id: message.id, result: { protocolVersion: 1, agentCapabilities: {} } });
    } else if (message.method === "session/new") {
      send({ jsonrpc: "2.0", id: message.id, result: { sessionId: "empty-session" } });
    } else if (message.method === "session/prompt") {
      send({
        jsonrpc: "2.0",
        method: "session/update",
        params: {
          sessionId: "empty-session",
          update: {
            sessionUpdate: "tool_call",
            toolCallId: "tool-empty",
            title: "Read memory",
            rawInput: { command: "test -f .detach/memory/MEMORY.md" }
          }
        }
      });
      send({ jsonrpc: "2.0", id: message.id, result: { stopReason: "end_turn" } });
    }
  }
}
`);
    const agent = new ACPAgentProcess({
      command: process.execPath,
      args: [fakeAgent.path],
      cwd: process.cwd(),
      activityAgent: "hosted",
      callbacks: {
        onActivity() {},
        onChunk() {},
      },
    });

    try {
      await expect(agent.run("hello")).rejects.toThrow(
        "completed its tool call but returned no final response",
      );
    } finally {
      fakeAgent.cleanup();
    }
  });

  test("injects MCP servers, streams text, and auto-approves a trusted tool", async () => {
    const fakeAgent = createTempTextFile("detach-fake-acp-", "agent.ts", `
let buffer = "";
let promptRequestId;

function send(message) {
  process.stdout.write(JSON.stringify(message) + "\\n");
}

for await (const chunk of Bun.stdin.stream()) {
  buffer += Buffer.from(chunk).toString("utf8");
  const lines = buffer.split(/\\r?\\n/);
  buffer = lines.pop() || "";

  for (const line of lines) {
    if (!line.trim()) continue;
    const message = JSON.parse(line);

    if (message.method === "initialize") {
      send({ jsonrpc: "2.0", id: message.id, result: { protocolVersion: 1, agentCapabilities: {} } });
    } else if (message.method === "session/new") {
      if (message.params.mcpServers[0].name !== "detach_browser_tools") process.exit(4);
      send({ jsonrpc: "2.0", id: message.id, result: { sessionId: "fake-session" } });
    } else if (message.method === "session/prompt") {
      promptRequestId = message.id;
      send({
        jsonrpc: "2.0",
        method: "session/update",
        params: {
          sessionId: "fake-session",
          update: {
            sessionUpdate: "tool_call",
            toolCallId: "tool-1",
            title: "Check browser status",
            rawInput: { name: "detach_browser_tools__detach_browser_status" }
          }
        }
      });
      send({
        jsonrpc: "2.0",
        id: 99,
        method: "session/request_permission",
        params: {
          sessionId: "fake-session",
          toolCall: { toolCallId: "tool-1" },
          options: [
            { optionId: "allow", name: "Allow", kind: "allow_once" },
            { optionId: "reject", name: "Reject", kind: "reject_once" }
          ]
        }
      });
    } else if (message.id === 99 && message.result?.outcome?.optionId === "allow") {
      send({
        jsonrpc: "2.0",
        method: "session/update",
        params: {
          sessionId: "fake-session",
          update: {
            sessionUpdate: "agent_message_chunk",
            content: { type: "text", text: "ACP OK" }
          }
        }
      });
      send({ jsonrpc: "2.0", id: promptRequestId, result: { stopReason: "end_turn" } });
    }
  }
}
`);
    const chunks: string[] = [];
    let permissionPrompts = 0;
    const agent = new ACPAgentProcess({
      command: process.execPath,
      args: [fakeAgent.path],
      cwd: process.cwd(),
      activityAgent: "opencode",
      mcpServers: [{
        id: "detach-browser-tools",
        name: "Detach Browser",
        transport: "stdio",
        command: "/tmp/detach-runtime",
        args: ["--mcp-browser-tools"],
        approvalPolicy: "auto-approve",
        toolNames: ["detach_browser_status"],
        enabled: true,
        created_at: 0,
        updated_at: 0,
      }],
      callbacks: {
        onActivity() {},
        onChunk(text) { chunks.push(text); },
        async onPermission() {
          permissionPrompts += 1;
          return false;
        },
      },
    });

    try {
      await expect(agent.run("test")).resolves.toEqual({ text: "ACP OK" });
      expect(chunks).toEqual(["ACP OK"]);
      expect(permissionPrompts).toBe(0);
    } finally {
      fakeAgent.cleanup();
    }
  });
});
