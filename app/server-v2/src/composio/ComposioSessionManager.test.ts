import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { SqliteComposioSessions } from "../history/SqliteComposioSessions";
import { SqliteMCPServers } from "../history/SqliteMCPServers";
import { ComposioSessionManager } from "./ComposioSessionManager";

const temporaryDirectories: string[] = [];

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

function stores() {
  const directory = mkdtempSync(join(tmpdir(), "detach-composio-session-"));
  temporaryDirectories.push(directory);
  return {
    mcpServers: new SqliteMCPServers(join(directory, "mcp.sqlite")),
    sessions: new SqliteComposioSessions(join(directory, "sessions.sqlite")),
  };
}

describe("ComposioSessionManager", () => {
  test("uses the paid control plane and installs a direct MCP session", async () => {
    const { mcpServers, sessions } = stores();
    const requests: Array<{ action: string; authorization: string | null }> = [];
    const fetcher = (async (_input: string | URL | Request, init?: RequestInit) => {
      const body = JSON.parse(String(init?.body)) as { action: string };
      requests.push({
        action: body.action,
        authorization: new Headers(init?.headers).get("authorization"),
      });

      if (body.action === "access") {
        return Response.json({ enabled: true, plan: "pro" });
      }
      if (body.action === "integrations") {
        return Response.json({
          items: [{ slug: "gmail", name: "Gmail", logo: "https://example.com/gmail.svg" }],
          total: 1,
          hasMore: false,
          offset: 0,
          limit: 10,
        });
      }
      if (body.action === "connect") {
        return Response.json({ connection: { id: "ca_gmail", status: "ACTIVE" } });
      }
      if (body.action === "connections") {
        return Response.json({
          items: [{
            slug: "gmail",
            name: "Gmail",
            connection: {
              isActive: true,
              connectedAccount: { id: "ca_gmail", status: "ACTIVE" },
            },
          }],
        });
      }
      if (body.action === "session") {
        return Response.json({
          session: {
            id: "trs_gmail",
            mode: "execute",
            mcp: {
              type: "http",
              url: "https://mcp.composio.dev/session/trs_gmail",
              headers: { authorization: "Bearer session-scoped" },
            },
          },
        });
      }
      throw new Error(`Unexpected action: ${body.action}`);
    }) as typeof fetch;

    const manager = new ComposioSessionManager(mcpServers, sessions, { fetcher });
    manager.configureHostedControlPlane({
      endpoint: "https://detach.example",
      accessToken: "supabase-user-token",
    });

    const integrations = await manager.listIntegrations({ userId: "user-123", limit: 10 });
    expect(integrations.type).toBe("composio_integrations");
    if (integrations.type === "composio_integrations") {
      expect(integrations.configured).toBe(true);
      expect(integrations.integrations[0]?.id).toBe("gmail");
    }

    const result = await manager.connectToolkit({ toolkit: "gmail", userId: "user-123" });
    expect(result.messages.some((message) => message.type === "mcp_server_added")).toBe(true);
    expect(mcpServers.list().find((server) => server.name === "Composio MCP")?.url)
      .toBe("https://mcp.composio.dev/session/trs_gmail");
    expect(requests.every((request) => request.authorization === "Bearer supabase-user-token")).toBe(true);
  });

  test("disables an existing local Composio server when the user is free", async () => {
    const { mcpServers, sessions } = stores();
    const existing = mcpServers.add({
      name: "Composio MCP",
      transport: "http",
      url: "https://mcp.composio.dev/session/old",
      headers: { authorization: "Bearer old-session" },
      enabled: true,
      approvalPolicy: "auto-approve",
    });
    const fetcher = (async () => Response.json({
      error: {
        code: "composio_paid_plan_required",
        message: "Composio integrations require an active paid Detach plan.",
      },
    }, { status: 403 })) as unknown as typeof fetch;

    const manager = new ComposioSessionManager(mcpServers, sessions, { fetcher });
    manager.configureHostedControlPlane({
      endpoint: "https://detach.example",
      accessToken: "free-user-token",
    });

    expect(await manager.refreshAccess()).toBe(false);
    expect(mcpServers.get(existing.id)?.enabled).toBe(false);
  });
});
