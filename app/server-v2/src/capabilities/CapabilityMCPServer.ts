import { CAPABILITY_BROKER_ID } from "./CapabilityConstants";

const DEFAULT_RUNTIME_URL = "http://127.0.0.1:3847";

export const CAPABILITY_MCP_TOOLS = [
  tool(
    "detach_capabilities_list",
    "List Detach's compact first-party capability directory. This returns availability and operation counts, not every operation schema.",
    { query: { type: "string", description: "Optional capability name or task keyword." } },
  ),
  tool(
    "detach_capability_describe",
    "Load the operation schemas for one capability only. Call this after listing capabilities and before invoking an operation.",
    { capabilityId: { type: "string", enum: ["browser", "macos", "secrets"] } },
    ["capabilityId"],
  ),
  tool(
    "detach_capability_invoke",
    "Invoke one operation from a described capability. Keep the arguments object limited to the operation's documented fields.",
    {
      capabilityId: { type: "string", enum: ["browser", "macos", "secrets"] },
      toolName: { type: "string" },
      arguments: { type: "object", additionalProperties: true },
    },
    ["capabilityId", "toolName"],
  ),
] as const;

export const CAPABILITY_TOOL_NAMES = CAPABILITY_MCP_TOOLS.map((item) => item.name);

export async function runCapabilityMCPServer() {
  const server = new CapabilityMCPServer(resolveRuntimeUrl());
  await server.run();
}

class CapabilityMCPServer {
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
            serverInfo: { name: CAPABILITY_BROKER_ID, version: "0.1.0" },
          },
        });
        return;
      case "tools/list":
        this.write({ jsonrpc: "2.0", id: request.id, result: { tools: CAPABILITY_MCP_TOOLS } });
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
    const tool = CAPABILITY_MCP_TOOLS.find((item) => item.name === name);
    if (!tool) {
      this.write({
        jsonrpc: "2.0",
        id: request.id,
        error: { code: -32602, message: `Unknown tool: ${name}` },
      });
      return;
    }

    try {
      const args = asRecord(params.arguments);
      const result = await this.callRuntime(name, args);
      this.write({ jsonrpc: "2.0", id: request.id, result: { content: mcpContent(result) } });
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

  private async callRuntime(name: string, args: Record<string, unknown>) {
    if (name === "detach_capabilities_list") {
      const query = typeof args.query === "string" && args.query.trim() ? `?query=${encodeURIComponent(args.query.trim())}` : "";
      return this.request(`/api/agent/capabilities${query}`, { method: "GET" });
    }

    if (name === "detach_capability_describe") {
      return this.request("/api/agent/capabilities/describe", {
        method: "POST",
        body: JSON.stringify({ capabilityId: args.capabilityId }),
      });
    }

    return this.request("/api/agent/capabilities/invoke", {
      method: "POST",
      body: JSON.stringify({
        capabilityId: args.capabilityId,
        toolName: args.toolName,
        arguments: asRecord(args.arguments),
        runId: resolveRunId(),
      }),
    });
  }

  private async request(path: string, init: RequestInit) {
    const response = await fetch(`${this.runtimeUrl}${path}`, {
      ...init,
      headers: {
        ...runtimeHeaders(),
        ...(init.headers ?? {}),
      },
    });
    const json = await response.json() as { ok?: boolean; result?: unknown; capabilities?: unknown; error?: string };
    if (!response.ok || !json.ok) throw new Error(json.error || "Detach capability request failed");
    return "result" in json ? json.result : json.capabilities;
  }

  private write(message: unknown) {
    process.stdout.write(`${JSON.stringify(message)}\n`);
  }
}

interface MCPRequest {
  id?: string | number | null;
  method?: string;
  params?: unknown;
}

function tool(name: string, description: string, properties: Record<string, unknown>, required: string[] = []) {
  return {
    name,
    description,
    inputSchema: { type: "object", properties, required, additionalProperties: false },
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function resolveRuntimeUrl() {
  return Bun.env.DETACH_RUNTIME_URL?.trim() || DEFAULT_RUNTIME_URL;
}

function resolveRunId() {
  return Bun.env.DETACH_CAPABILITY_RUN_ID?.trim() || undefined;
}

function runtimeHeaders() {
  const token = Bun.env.DETACH_RUNTIME_TOKEN?.trim();
  if (!token) throw new Error("DETACH_RUNTIME_TOKEN is required");
  return {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
}

function mcpContent(result: unknown) {
  if (!result || typeof result !== "object" || Array.isArray(result)) {
    return [{ type: "text", text: boundedJson(result) }];
  }
  const record = asRecord(result);
  const imageBase64 = typeof record.imageBase64 === "string" ? record.imageBase64 : undefined;
  const mimeType = typeof record.mimeType === "string" ? record.mimeType : "image/png";
  const images = Array.isArray(record.images)
    ? record.images.map(asRecord).filter((image) => typeof image.data === "string")
    : [];
  const summary = { ...record };
  delete summary.imageBase64;
  delete summary.images;
  const content: Array<Record<string, unknown>> = [{ type: "text", text: boundedJson(summary) }];
  if (imageBase64) content.push({ type: "image", data: imageBase64, mimeType });
  for (const image of images) {
    content.push({
      type: "image",
      data: image.data as string,
      mimeType: typeof image.mimeType === "string" ? image.mimeType : "image/png",
    });
  }
  return content;
}

function boundedJson(value: unknown) {
  const text = JSON.stringify(value, null, 2);
  const maxChars = 40_000;
  return text.length <= maxChars ? text : `${text.slice(0, maxChars)}\n...[result truncated by Detach]`;
}
