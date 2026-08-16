const DEFAULT_RUNTIME_URL = "http://127.0.0.1:3847";

export async function runBrowserMCPServer() {
  const server = new BrowserMCPServer(resolveRuntimeUrl());
  await server.run();
}

class BrowserMCPServer {
  private buffer = "";
  private pending = new Set<Promise<void>>();

  constructor(private readonly runtimeUrl: string) {}

  async run() {
    for await (const chunk of Bun.stdin.stream()) {
      this.buffer += Buffer.from(chunk).toString("utf8");
      this.consumeBuffer();
    }

    if (this.buffer.trim()) {
      const pending = this.handleLine(this.buffer.trim());
      this.pending.add(pending);
      pending.finally(() => this.pending.delete(pending));
      this.buffer = "";
    }

    await Promise.allSettled(this.pending);
  }

  private consumeBuffer() {
    const lines = this.buffer.split(/\r?\n/);
    this.buffer = lines.pop() ?? "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      const pending = this.handleLine(trimmed).catch((error) => {
        this.write({
          jsonrpc: "2.0",
          id: null,
          error: {
            code: -32603,
            message: error instanceof Error ? error.message : String(error),
          },
        });
      });
      this.pending.add(pending);
      pending.finally(() => this.pending.delete(pending));
    }
  }

  private async handleLine(line: string) {
    const request = JSON.parse(line) as MCPRequest;

    if (!("id" in request)) {
      return;
    }

    switch (request.method) {
      case "initialize":
        this.write({
          jsonrpc: "2.0",
          id: request.id,
          result: {
            protocolVersion: "2024-11-05",
            capabilities: {
              tools: {},
            },
            serverInfo: {
              name: "detach-browser",
              version: "0.4.0",
            },
          },
        });
        return;

      case "tools/list":
        this.write({
          jsonrpc: "2.0",
          id: request.id,
          result: {
            tools: BROWSER_TOOLS,
          },
        });
        return;

      case "tools/call":
        await this.handleToolCall(request);
        return;

      default:
        this.write({
          jsonrpc: "2.0",
          id: request.id,
          error: {
            code: -32601,
            message: `Unknown method: ${request.method}`,
          },
        });
    }
  }

  private async handleToolCall(request: MCPRequest) {
    const params = asRecord(request.params);
    const name = typeof params.name === "string" ? params.name : "";
    const args = asRecord(params.arguments);
    const tool = BROWSER_TOOLS.find((item) => item.name === name);

    if (!tool) {
      this.write({
        jsonrpc: "2.0",
        id: request.id,
        error: {
          code: -32602,
          message: `Unknown tool: ${name}`,
        },
      });
      return;
    }

    try {
      const result = await this.callBrowserTool(name, args);
      this.write({
        jsonrpc: "2.0",
        id: request.id,
        result: {
          content: toolContent(name, result),
        },
      });
    } catch (error) {
      this.write({
        jsonrpc: "2.0",
        id: request.id,
        result: {
          isError: true,
          content: [
            {
              type: "text",
              text: error instanceof Error ? error.message : String(error),
            },
          ],
        },
      });
    }
  }

  private async callBrowserTool(name: string, args: Record<string, unknown>) {
    const command = BROWSER_TOOL_COMMANDS[name] ?? name.replace(/^detach_/, "browser.");
    const response = await fetch(`${this.runtimeUrl}/api/browser/command`, {
      method: "POST",
      headers: runtimeHeaders(),
      body: JSON.stringify({
        command,
        payload: args,
        runId: resolveRunId(),
      }),
    });

    const json = await response.json() as { ok?: boolean; result?: unknown; error?: string };
    if (!response.ok || !json.ok) {
      throw new Error(json.error || `Browser command failed: ${command}`);
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

export const BROWSER_TOOL_COMMANDS: Record<string, string> = {
  detach_browser_execute: "browser.execute_code",
};

export const BROWSER_TOOLS = [
  tool(
    "detach_browser_execute",
    "Run a safe Playwright-shaped JavaScript program in the user's focused signed-in Chrome window. Page supports status/goto/open/url/title/snapshot/evaluate, frameLocator, tables, task events, dialogs, visual screenshots, media captions/frames, and bounded document artifacts including PDF text. Locators support strict label/role/placeholder/CSS targeting, stable frame-scoped refs, live reads, validation, drag/range input, file uploads, bounding boxes, and element screenshots. Use page.artifact(urlOrLocator) for task-owned web documents and page.waitForEvent('download'|'popup'|'navigation') for asynchronous browser state. Return { taskComplete: true, evidence: ... } only after direct verification. Multiple actions and local transforms run in one call without filesystem, process, imports, or unrestricted network access.",
    {
      code: { type: "string", description: "Playwright-shaped JavaScript. Usually return the final verified value or snapshot." },
      timeoutMs: { type: "number", minimum: 1000, maximum: 300000 },
    },
    ["code"]
  ),
];

export const BROWSER_TOOL_NAMES = BROWSER_TOOLS.map((tool) => tool.name);

function tool(name: string, description: string, properties: Record<string, unknown>, required: string[] = []) {
  return {
    name,
    description,
    inputSchema: {
      type: "object",
      properties,
      required,
      additionalProperties: false,
    },
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function resolveRuntimeUrl() {
  return Bun.env.DETACH_BROWSER_RUNTIME_HTTP?.trim() || Bun.env.DETACH_RUNTIME_URL?.trim() || DEFAULT_RUNTIME_URL;
}

function runtimeHeaders() {
  const token = Bun.env.DETACH_RUNTIME_TOKEN?.trim();
  if (!token) throw new Error("DETACH_RUNTIME_TOKEN is required");
  return {
    "Authorization": `Bearer ${token}`,
    "Content-Type": "application/json",
  };
}

function resolveRunId() {
  return Bun.env.DETACH_BROWSER_RUN_ID?.trim() || undefined;
}

export function toolContent(name: string, result: unknown) {
  const record = asRecord(result);
  const images = Array.isArray(record.images) ? record.images.map(asRecord).filter((image) => typeof image.data === "string") : [];
  const summary = { ...record };
  delete summary.images;
  return [
    ...images.map((image) => ({
      type: "image",
      data: image.data as string,
      mimeType: typeof image.mimeType === "string" ? image.mimeType : "image/png",
    })),
    { type: "text", text: JSON.stringify(summary, null, 2) },
  ];
}
