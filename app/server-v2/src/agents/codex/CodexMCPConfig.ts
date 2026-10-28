import type { MCPServerConfig } from "../../protocol/messages";
import { autoApprovedMCPServers } from "../MCPConfig";

export function codexMCPArgs(servers: MCPServerConfig[] = []) {
  return servers.filter((server) => server.enabled).flatMap(codexMCPConfigArgs);
}

function codexMCPConfigArgs(server: MCPServerConfig) {
  const key = sanitizeMCPKey(server.id || server.name);
  const args: string[] = [];

  if ((server.transport === "http" || server.transport === "sse") && server.url?.trim()) {
    args.push("-c", `mcp_servers.${key}.url=${tomlString(server.url.trim())}`);
  }

  if (server.transport === "stdio" && server.command?.trim()) {
    args.push("-c", `mcp_servers.${key}.command=${tomlString(server.command.trim())}`);
    if (server.args?.length) {
      args.push("-c", `mcp_servers.${key}.args=${tomlStringArray(server.args)}`);
    }
    for (const [envKey, envValue] of Object.entries(server.env ?? {})) {
      if (!isSafeConfigKey(envKey)) continue;
      args.push("-c", `mcp_servers.${key}.env.${envKey}=${tomlString(envValue)}`);
    }
  }

  const envHttpHeaders = tomlInlineStringMap(codexHTTPHeaderEnvMap(key, server.headers));
  if (envHttpHeaders) {
    args.push("-c", `mcp_servers.${key}.env_http_headers=${envHttpHeaders}`);
  }

  if (autoApprovedMCPServers([server]).length > 0) {
    // Preserve Detach's shared trust policy for built-in servers.
    args.push("-c", `mcp_servers.${key}.default_tools_approval_mode=${tomlString("approve")}`);
  }

  return args;
}

export function buildCodexMCPEnv(mcpServers: MCPServerConfig[] = []) {
  const env: Record<string, string> = {};

  for (const server of mcpServers.filter((item) => item.enabled)) {
    if (server.transport !== "http" && server.transport !== "sse") continue;
    const key = sanitizeMCPKey(server.id || server.name);

    for (const [headerName, value] of Object.entries(server.headers ?? {})) {
      if (!headerName.trim() || !value.trim()) continue;
      env[codexHTTPHeaderEnvVarName(key, headerName)] = value;
    }
  }

  return env;
}

function codexHTTPHeaderEnvMap(serverKey: string, headers?: Record<string, string>) {
  const entries = Object.entries(headers ?? {}).filter(([headerName, value]) => headerName.trim() && value.trim());
  if (entries.length === 0) return undefined;

  return Object.fromEntries(
    entries.map(([headerName]) => [headerName, codexHTTPHeaderEnvVarName(serverKey, headerName)])
  );
}

function codexHTTPHeaderEnvVarName(serverKey: string, headerName: string) {
  const normalizedServer = serverKey.toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/^_|_$/g, "");
  const normalizedHeader = headerName.toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/^_|_$/g, "");
  return `DETACH_MCP_${normalizedServer || "SERVER"}_${normalizedHeader || "HEADER"}`;
}

function sanitizeMCPKey(value: string) {
  const sanitized = value.toLowerCase().replace(/[^a-z0-9_]/g, "_").replace(/_+/g, "_").replace(/^_|_$/g, "");
  return sanitized || `mcp_${Date.now().toString(36)}`;
}

function isSafeConfigKey(value: string) {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(value);
}

function tomlString(value: string) {
  return JSON.stringify(value);
}

function tomlStringArray(values: string[]) {
  return `[${values.map(tomlString).join(", ")}]`;
}

function tomlInlineStringMap(values?: Record<string, string>) {
  const entries = Object.entries(values ?? {}).filter(
    ([key, value]) => key.trim() && typeof value === "string" && value.trim()
  );

  if (entries.length === 0) return undefined;

  return `{${entries.map(([key, value]) => `${tomlString(key)}=${tomlString(value)}`).join(", ")}}`;
}

