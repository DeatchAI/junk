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
              version: "0.1.0",
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
          content: [
            {
              type: "text",
              text: JSON.stringify(result, null, 2),
            },
          ],
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
    const command = TOOL_COMMANDS[name] ?? name.replace(/^detach_/, "browser.");
    const response = await fetch(`${this.runtimeUrl}/api/browser/command`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        command,
        payload: args,
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

const TOOL_COMMANDS: Record<string, string> = {
  detach_browser_status: "browser.status",
  detach_browser_list_tabs: "browser.list_tabs",
  detach_browser_active_tab: "browser.get_active_tab",
  detach_browser_open_tab: "browser.open_tab",
  detach_browser_navigate: "browser.navigate",
  detach_browser_snapshot: "browser.snapshot",
  detach_browser_extract_text: "browser.extract_text",
  detach_browser_get_selection: "browser.get_selection",
  detach_browser_click: "browser.click",
  detach_browser_type: "browser.type",
  detach_browser_select: "browser.select",
  detach_browser_scroll: "browser.scroll",
  detach_browser_screenshot: "browser.screenshot",
};

const BROWSER_TOOLS = [
  tool("detach_browser_status", "Check whether the Detach Chrome extension is connected.", {}),
  tool("detach_browser_list_tabs", "List open Chrome tabs visible to the Detach extension.", {}),
  tool("detach_browser_active_tab", "Get the active Chrome tab and whether Chrome allows extension automation on it.", {}),
  tool("detach_browser_open_tab", "Open an http/https URL in a new Chrome tab.", {
    url: { type: "string" },
    active: { type: "boolean" },
  }, ["url"]),
  tool("detach_browser_navigate", "Navigate a Chrome tab to a URL.", {
    url: { type: "string" },
    tabId: { type: "number" },
  }, ["url"]),
  tool("detach_browser_snapshot", "Read the active page title, URL, visible text, headings, and interactive element refs.", {
    tabId: { type: "number" },
    maxTextLength: { type: "number" },
    maxElements: { type: "number" },
  }),
  tool("detach_browser_extract_text", "Extract page text from a Chrome tab.", {
    tabId: { type: "number" },
    maxLength: { type: "number" },
  }),
  tool("detach_browser_get_selection", "Read the current text selection in a Chrome tab.", {
    tabId: { type: "number" },
  }),
  tool("detach_browser_click", "Click a page element by ref, CSS selector, or visible text.", targetSchema()),
  tool("detach_browser_type", "Type text into a page element by ref, CSS selector, or visible text.", {
    ...targetSchema(),
    inputText: { type: "string" },
    append: { type: "boolean" },
  }, ["inputText"]),
  tool("detach_browser_select", "Choose a value in a select menu.", {
    ...targetSchema(),
    value: { type: "string" },
  }, ["value"]),
  tool("detach_browser_scroll", "Scroll the page or scroll an element into view.", {
    ...targetSchema(),
    x: { type: "number" },
    y: { type: "number" },
    deltaX: { type: "number" },
    deltaY: { type: "number" },
    smooth: { type: "boolean" },
    block: { type: "string" },
  }),
  tool("detach_browser_screenshot", "Capture a visible-tab screenshot as a data URL.", {
    tabId: { type: "number" },
    format: { type: "string", enum: ["png", "jpeg"] },
    quality: { type: "number" },
  }),
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

function targetSchema() {
  return {
    tabId: { type: "number" },
    ref: { type: "string" },
    selector: { type: "string" },
    targetText: { type: "string" },
  };
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function resolveRuntimeUrl() {
  return Bun.env.DETACH_BROWSER_RUNTIME_HTTP?.trim() || Bun.env.DETACH_RUNTIME_URL?.trim() || DEFAULT_RUNTIME_URL;
}
