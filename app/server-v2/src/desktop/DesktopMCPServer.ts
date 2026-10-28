import { MACOS_TOOLS, MACOS_TOOL_COMMANDS } from "./DesktopTools";
import { MACOS_GUIDE } from "../capabilities/CapabilityGuides";

const DEFAULT_RUNTIME_URL = "http://127.0.0.1:3847";

export async function runDesktopMCPServer() {
  const server = new DesktopMCPServer(resolveRuntimeUrl());
  await server.run();
}

class DesktopMCPServer {
  private buffer = "";
  private pending = new Set<Promise<void>>();

  constructor(private readonly runtimeUrl: string) {}

  async run() {
    for await (const chunk of Bun.stdin.stream()) {
      this.buffer += Buffer.from(chunk).toString("utf8");
      this.consumeBuffer();
    }

    if (this.buffer.trim()) this.track(this.handleLine(this.buffer.trim()));
    this.buffer = "";
    await Promise.allSettled(this.pending);
  }

  private consumeBuffer() {
    const lines = this.buffer.split(/\r?\n/);
    this.buffer = lines.pop() ?? "";
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed) this.track(this.handleLine(trimmed));
    }
  }

  private track(promise: Promise<void>) {
    const tracked = promise.catch((error) => {
      this.write({
        jsonrpc: "2.0",
        id: null,
        error: { code: -32603, message: error instanceof Error ? error.message : String(error) },
      });
    });
    this.pending.add(tracked);
    tracked.finally(() => this.pending.delete(tracked));
  }

  private async handleLine(line: string) {
    const request = JSON.parse(line) as MCPRequest;
    if (!("id" in request)) return;

    switch (request.method) {
      case "initialize":
        this.write({
          jsonrpc: "2.0",
          id: request.id,
          result: {
            protocolVersion: "2024-11-05",
            capabilities: { tools: {} },
            serverInfo: { name: "detach-macos", version: "0.1.0" },
            instructions: MACOS_GUIDE,
          },
        });
        return;
      case "tools/list":
        this.write({ jsonrpc: "2.0", id: request.id, result: { tools: MACOS_TOOLS } });
        return;
      case "tools/call":
        await this.handleToolCall(request);
        return;
      default:
        this.write({
          jsonrpc: "2.0",
          id: request.id,
          error: { code: -32601, message: `Unknown method: ${request.method}` },
        });
    }
  }

  private async handleToolCall(request: MCPRequest) {
    const params = asRecord(request.params);
    const name = typeof params.name === "string" ? params.name : "";
    const args = asRecord(params.arguments);
    const tool = MACOS_TOOLS.find((item) => item.name === name);

    if (!tool) {
      this.write({
        jsonrpc: "2.0",
        id: request.id,
        error: { code: -32602, message: `Unknown tool: ${name}` },
      });
      return;
    }

    try {
      const result = await this.callDesktopTool(name, args);
      this.write({
        jsonrpc: "2.0",
        id: request.id,
        result: { content: mcpContent(result) },
      });
    } catch (error) {
      this.write({
        jsonrpc: "2.0",
        id: request.id,
        result: {
          isError: true,
          content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }],
        },
      });
    }
  }

  private async callDesktopTool(name: string, args: Record<string, unknown>) {
    const command = MACOS_TOOL_COMMANDS[name];
    const response = await fetch(`${this.runtimeUrl}/api/desktop/command`, {
      method: "POST",
      headers: runtimeHeaders(),
      body: JSON.stringify({ command, payload: args, runId: Bun.env.DETACH_DESKTOP_RUN_ID?.trim() }),
    });

    const json = await response.json() as { ok?: boolean; result?: unknown; error?: string };
    if (!response.ok || !json.ok) {
      throw new Error(json.error || `macOS command failed: ${command}`);
    }
    return json.result;
  }

  private write(message: unknown) {
    process.stdout.write(`${JSON.stringify(message)}\n`);
  }
}

interface MCPRequest {
  jsonrpc?: "2.0";
  id?: string | number | null;
  method?: string;
  params?: unknown;
}

export { MACOS_TOOLS, MACOS_TOOL_COMMANDS, MACOS_TOOL_NAMES } from "./DesktopTools";

function mcpContent(result: unknown) {
  const record = asRecord(result);
  const imageBase64 = typeof record.imageBase64 === "string" ? record.imageBase64 : undefined;
  const mimeType = typeof record.mimeType === "string" ? record.mimeType : "image/png";
  if (!imageBase64) {
    return [{ type: "text", text: JSON.stringify(result, null, 2) }];
  }

  const { imageBase64: _discarded, ...metadata } = record;
  return [
    { type: "text", text: JSON.stringify(metadata, null, 2) },
    { type: "image", data: imageBase64, mimeType },
  ];
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function resolveRuntimeUrl() {
  return Bun.env.DETACH_DESKTOP_RUNTIME_HTTP?.trim() || Bun.env.DETACH_RUNTIME_URL?.trim() || DEFAULT_RUNTIME_URL;
}

function runtimeHeaders() {
  const token = Bun.env.DETACH_RUNTIME_TOKEN?.trim();
  if (!token) throw new Error("DETACH_RUNTIME_TOKEN is required");
  return {
    "Authorization": `Bearer ${token}`,
    "Content-Type": "application/json",
  };
}
