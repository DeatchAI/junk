import type { MCPServerConfig } from "../protocol/messages";

/**
 * Older clients omit `selectedIds`, which preserves the historical behavior of
 * loading every enabled server. The current runtime resolves omitted macOS
 * selections to the compact Detach capability broker before this function is
 * called. An explicit empty array intentionally attaches no MCP capability.
 */
export function selectMCPServers(
  available: MCPServerConfig[],
  selectedIds?: string[]
) {
  if (!selectedIds) return available;

  const selected = new Set(selectedIds.filter(Boolean));
  return available.filter((server) => selected.has(server.id));
}
