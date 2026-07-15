const DEFAULT_RUNTIME_URL = "http://127.0.0.1:3847";

export const SECRETS_TOOL_NAMES = ["detach_secrets_search_credential", "detach_secrets_use_credential"];

export async function runSecretsMCPServer() {
  const server = new SecretsMCPServer(Bun.env.DETACH_RUNTIME_URL?.trim() || DEFAULT_RUNTIME_URL);
  await server.run();
}

class SecretsMCPServer {
  private buffer = "";
  constructor(private readonly runtimeUrl: string) {}

  async run() {
    for await (const chunk of Bun.stdin.stream()) {
      this.buffer += Buffer.from(chunk).toString("utf8");
      const lines = this.buffer.split(/\r?\n/);
      this.buffer = lines.pop() ?? "";
      for (const line of lines) if (line.trim()) await this.handleLine(line.trim());
    }
  }

  private async handleLine(line: string) {
    const request = JSON.parse(line) as { id?: string | number | null; method?: string; params?: { name?: string; arguments?: Record<string, unknown> } };
    if (!("id" in request)) return;
    if (request.method === "initialize") return this.write(request.id, { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "detach-secrets", version: "0.1.0" } });
    if (request.method === "tools/list") return this.write(request.id, { tools: TOOLS });
    if (request.method !== "tools/call") return this.error(request.id, "Unknown method");

    const name = request.params?.name;
    if (!TOOLS.some((tool) => tool.name === name)) return this.error(request.id, "Unknown tool");
    try {
      const response = await fetch(`${this.runtimeUrl}/api/secrets/command`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ command: name === "detach_secrets_search_credential" ? "search" : "use", payload: request.params?.arguments ?? {} }),
      });
      const json = await response.json() as { ok?: boolean; result?: unknown; error?: string };
      if (!response.ok || !json.ok) throw new Error(json.error || "Secure credential command failed");
      this.write(request.id, { content: [{ type: "text", text: JSON.stringify(json.result, null, 2) }] });
    } catch (error) {
      this.write(request.id, { isError: true, content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }] });
    }
  }

  private write(id: string | number | null | undefined, result: unknown) { process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id, result })}\n`); }
  private error(id: string | number | null | undefined, message: string) { process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", id, error: { code: -32601, message } })}\n`); }
}

const TOOLS = [
  tool("detach_secrets_search_credential", "Search locally stored credential labels for a site or app. Returns safe metadata only, never passwords or tokens.", { query: { type: "string" }, origin: { type: "string" } }, ["query"]),
  tool("detach_secrets_use_credential", "Trigger Touch ID to fill a browser login without exposing any credential values. Use only after inspecting the login form.", { credentialId: { type: "string" }, origin: { type: "string" }, tabId: { type: "number" }, usernameRef: { type: "string" }, passwordRef: { type: "string" } }, ["credentialId", "origin", "usernameRef", "passwordRef"]),
];

function tool(name: string, description: string, properties: Record<string, unknown>, required: string[] = []) { return { name, description, inputSchema: { type: "object", properties, required } }; }
