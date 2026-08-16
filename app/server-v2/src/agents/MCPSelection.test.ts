import { describe, expect, test } from "bun:test";

import { selectMCPServers } from "./MCPSelection";
import type { MCPServerConfig } from "../protocol/messages";

describe("composer MCP selection", () => {
  const available = [server("detach-browser-tools"), server("detach-macos-tools"), server("github")];

  test("keeps every enabled server available for legacy callers", () => {
    expect(selectMCPServers(available).map((server) => server.id)).toEqual(available.map((server) => server.id));
  });

  test("injects only the MCP capabilities attached to the composer", () => {
    expect(selectMCPServers(available, ["github", "detach-browser-tools"]).map((server) => server.id)).toEqual([
      "detach-browser-tools",
      "github",
    ]);
  });

  test("treats an explicit empty attachment list as no MCP capabilities", () => {
    expect(selectMCPServers(available, [])).toEqual([]);
  });
});

function server(id: string): MCPServerConfig {
  return {
    id,
    name: id,
    transport: "stdio",
    command: "/tmp/mcp",
    enabled: true,
    created_at: 0,
    updated_at: 0,
  };
}
