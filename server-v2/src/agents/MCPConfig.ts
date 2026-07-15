import type { MCPServerConfig } from "../protocol/messages";

export function enabledMCPServers(servers: MCPServerConfig[] = []) {
  return servers.filter((server) => server.enabled);
}

export function autoApprovedMCPServers(servers: MCPServerConfig[] = []) {
  return enabledMCPServers(servers).filter((server) => server.approvalPolicy === "auto-approve");
}

export function buildClaudeMCPConfig(servers: MCPServerConfig[] = []) {
  return {
    mcpServers: Object.fromEntries(enabledMCPServers(servers).map((server) => [sanitizeMCPKey(server.id || server.name), claudeServerConfig(server)])),
  };
}

export function buildClaudeAllowedTools(servers: MCPServerConfig[] = []) {
  return autoApprovedMCPServers(servers).map(
    (server) => `mcp__${sanitizeMCPKey(server.id || server.name)}__*`
  );
}

export function buildACPMCPServers(servers: MCPServerConfig[] = []): ACPMCPServer[] {
  const result: ACPMCPServer[] = [];

  for (const server of enabledMCPServers(servers)) {
    const name = sanitizeMCPKey(server.id || server.name);

    if (server.transport === "stdio" && server.command?.trim()) {
      result.push({
        name,
        command: server.command.trim(),
        args: server.args ?? [],
        env: Object.entries(server.env ?? {}).map(([envName, value]) => ({ name: envName, value })),
      });
      continue;
    }

    if ((server.transport === "http" || server.transport === "sse") && server.url?.trim()) {
      result.push({
        type: server.transport,
        name,
        url: server.url.trim(),
        headers: Object.entries(server.headers ?? {}).map(([headerName, value]) => ({
          name: headerName,
          value,
          secret: true,
        })),
      });
    }
  }

  return result;
}

export function autoApprovedMCPToolIdentities(servers: MCPServerConfig[] = []) {
  return autoApprovedMCPServers(servers).flatMap((server) => {
    const key = sanitizeMCPKey(server.id || server.name);
    return [key, ...(server.toolNames ?? [])];
  });
}

export function sanitizeMCPKey(value: string) {
  const sanitized = value.toLowerCase().replace(/[^a-z0-9_]/g, "_").replace(/_+/g, "_").replace(/^_|_$/g, "");
  return sanitized || `mcp_${Date.now().toString(36)}`;
}

function claudeServerConfig(server: MCPServerConfig) {
  if ((server.transport === "http" || server.transport === "sse") && server.url?.trim()) {
    return {
      type: server.transport === "sse" ? "sse" : "http",
      url: server.url.trim(),
      headers: nonEmpty(server.headers),
    };
  }

  return {
    command: server.command ?? "",
    args: server.args ?? [],
    env: nonEmpty(server.env) ?? {},
  };
}

function nonEmpty(value?: Record<string, string>) {
  if (!value || Object.keys(value).length === 0) return undefined;
  return value;
}

export type ACPMCPServer =
  | {
      name: string;
      command: string;
      args: string[];
      env: Array<{ name: string; value: string }>;
    }
  | {
      type: "http" | "sse";
      name: string;
      url: string;
      headers: Array<{ name: string; value: string; secret: boolean }>;
    };
