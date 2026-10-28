import type { ChatRequest } from "../../protocol/messages";
import { buildClaudeMCPConfig, sanitizeMCPKey } from "../MCPConfig";

/** Run-local extension: no changes to ~/.pi, project files, or credentials. */
export function piRunExtension(request: ChatRequest, marker: string) {
  const servers = buildClaudeMCPConfig(request.mcpServers).mcpServers;
  const names = new Map(Object.keys(servers).map((key, index) => [key, piMCPServerName(marker, index)]));
  const registrations = Object.entries(servers).map(([key, config]) => ({
    name: names.get(key), config: { ...config, exposure: "direct" },
  }));
  if (registrations.some(({ config }) => "type" in config && config.type === "sse")) {
    throw new Error("Pi supports stdio and HTTP MCP servers, not legacy SSE. Use the server's HTTP endpoint.");
  }
  const manual = (request.mcpServers ?? []).filter((server) => server.enabled && server.approvalPolicy !== "auto-approve")
    .map((server) => `mcp__${names.get(sanitizeMCPKey(server.id || server.name))}__`);
  return `export default function(pi) {
    if (typeof pi.registerMcpServer !== "function") {
      throw new Error("Update Pi to a version with built-in MCP support before using it in Detach.");
    }
    for (const server of ${JSON.stringify(registrations)}) pi.registerMcpServer(server.name, server.config);
    pi.registerCommand(${JSON.stringify(marker)}, { description: "Detach integration ready", handler: async () => {} });
    pi.on("tool_call", async (event, ctx) => {
      const manual = ${JSON.stringify(manual)}.some(prefix => event.toolName.startsWith(prefix));
      if (event.toolName !== "bash" && !manual) return;
      const detail = event.toolName === "bash" ? String(event.input?.command ?? "Shell command") : event.toolName;
      const approved = ctx.hasUI && await ctx.ui.confirm("Allow this action?", detail);
      if (!approved) return { block: true, reason: "Action denied by the user in Detach." };
    });
  }`;
}

/** Keep model-facing function names short, even when a configured server ID is long. */
export function piMCPServerName(marker: string, index: number) {
  return "d" + marker.replace(/[^a-z0-9]/gi, "").slice(-10).toLowerCase() + "_" + index;
}
