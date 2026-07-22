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
    const command = TOOL_COMMANDS[name];
    const response = await fetch(`${this.runtimeUrl}/api/desktop/command`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ command, payload: args }),
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

const TOOL_COMMANDS: Record<string, string> = {
  detach_macos_status: "desktop.status",
  detach_macos_list_apps: "desktop.list_apps",
  detach_macos_list_windows: "desktop.list_windows",
  detach_macos_activate_app: "desktop.activate_app",
  detach_macos_open_app: "desktop.open_app",
  detach_macos_snapshot: "desktop.snapshot",
  detach_macos_screenshot: "desktop.screenshot",
  detach_macos_click: "desktop.click",
  detach_macos_type: "desktop.type",
  detach_macos_key: "desktop.key",
  detach_macos_scroll: "desktop.scroll",
};

const appTarget = {
  pid: { type: "number", description: "Process ID of a running application." },
  bundleId: { type: "string", description: "Application bundle identifier." },
  appName: { type: "string", description: "Localized application name." },
};

const MACOS_TOOLS = [
  tool("detach_macos_status", "Check the native macOS bridge and required Accessibility and Screen Recording permissions.", {}),
  tool("detach_macos_list_apps", "List running foreground-capable macOS applications.", {}),
  tool("detach_macos_list_windows", "List accessibility windows for an app, defaulting to the frontmost app.", appTarget),
  tool("detach_macos_activate_app", "Bring an already-running application to the foreground.", appTarget),
  tool("detach_macos_open_app", "Launch or foreground an application by bundle ID or application name.", {
    bundleId: appTarget.bundleId,
    appName: appTarget.appName,
  }),
  tool("detach_macos_snapshot", "Inspect a native app's accessibility tree and return fresh element refs. Prefer refs over coordinates.", {
    ...appTarget,
    maxDepth: { type: "number", minimum: 1, maximum: 12 },
    maxElements: { type: "number", minimum: 1, maximum: 1000 },
  }),
  tool("detach_macos_screenshot", "Capture the current macOS display. Requires Screen Recording permission and returns an MCP image.", {
    displayId: { type: "number" },
    maxWidth: { type: "number", minimum: 320, maximum: 3840 },
    showsCursor: { type: "boolean" },
  }),
  tool("detach_macos_click", "Click a recent accessibility ref, or explicit screen coordinates when no semantic element exists.", {
    ref: { type: "string" },
    x: { type: "number" },
    y: { type: "number" },
    button: { type: "string", enum: ["left", "right"] },
    clickCount: { type: "number", minimum: 1, maximum: 3 },
  }),
  tool("detach_macos_type", "Enter text into a focused or referenced editable element. Secure text fields are refused.", {
    ref: { type: "string" },
    text: { type: "string" },
    replace: { type: "boolean" },
  }, ["text"]),
  tool("detach_macos_key", "Press a key or keyboard shortcut in the active app.", {
    key: { type: "string", description: "A letter, digit, or named key such as return, tab, escape, delete, or arrow_up." },
    modifiers: {
      type: "array",
      items: { type: "string", enum: ["command", "option", "control", "shift", "fn"] },
    },
    repeat: { type: "number", minimum: 1, maximum: 20 },
  }, ["key"]),
  tool("detach_macos_scroll", "Scroll at the pointer or at explicit screen coordinates. Positive deltaY scrolls up; negative scrolls down.", {
    deltaX: { type: "number" },
    deltaY: { type: "number" },
    x: { type: "number" },
    y: { type: "number" },
  }),
];

export const MACOS_TOOL_NAMES = MACOS_TOOLS.map((item) => item.name);

function tool(name: string, description: string, properties: Record<string, unknown>, required: string[] = []) {
  return {
    name,
    description,
    inputSchema: { type: "object", properties, required, additionalProperties: false },
  };
}

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
