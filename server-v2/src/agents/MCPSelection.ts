import type { MCPServerConfig } from "../protocol/messages";

/**
 * Older clients omit `selectedIds`, which preserves the historical behavior of
 * loading every enabled server. The rich composer always sends an array, so an
 * empty array intentionally attaches no MCP capability to that request.
 */
export function selectMCPServers(
  available: MCPServerConfig[],
  selectedIds?: string[]
) {
  if (!selectedIds) return available;

  const selected = new Set(selectedIds.filter(Boolean));
  return available.filter((server) => selected.has(server.id));
}
