import { Composio, SessionPreset } from "@composio/core";
import { SqliteComposioSessions } from "../history/SqliteComposioSessions";
import { SqliteMCPServers, statusForServer } from "../history/SqliteMCPServers";
import type { ComposioConnection, ComposioIntegration, MCPServerConfig, ServerMessage } from "../protocol/messages";

interface ToolkitState {
  slug: string;
  name: string;
  logo?: string;
  isNoAuth?: boolean;
  connection?: {
    isActive?: boolean;
    connectedAccount?: {
      id: string;
      status?: string;
    };
  };
}

interface ToolkitListResponse {
  items: ToolkitState[];
  cursor?: string;
  totalPages?: number;
}

interface ComposioSession {
  sessionId: string;
  mcp: {
    type?: "http" | "sse";
    url: string;
    headers?: Record<string, string>;
  };
  toolkits: (options?: {
    limit?: number;
    cursor?: string;
    search?: string;
    isConnected?: boolean;
  }) => Promise<ToolkitListResponse>;
  authorize: (
    toolkit: string,
    options?: { callbackUrl?: string }
  ) => Promise<ConnectionRequest>;
}

interface ConnectionRequest {
  id: string;
  redirectUrl?: string | null;
  status?: string;
  waitForConnection: (timeout?: number) => Promise<ConnectedAccount>;
}

interface ConnectedAccount {
  id: string;
  status: string;
  toolkit?: {
    slug: string;
  };
}

export class ComposioSessionManager {
  private readonly sessionStore: SqliteComposioSessions;
  private readonly mcpServers: SqliteMCPServers;
  private readonly composio?: Composio;

  constructor(mcpServers: SqliteMCPServers, sessionStore = new SqliteComposioSessions()) {
    this.mcpServers = mcpServers;
    this.sessionStore = sessionStore;

    const apiKey = "ak_1sNxVXoLJAdiJDi20VbD" //Bun.env.COMPOSIO_API_KEY?.trim();
    if (apiKey) {
      this.composio = new Composio({
        apiKey,
        allowTracking: false,
        disableVersionCheck: true,
        host: "detach-runtime",
      });
    }
  }

  isConfigured() {
    return Boolean(this.composio);
  }

  async listIntegrations(input: { userId?: string; limit?: number; offset?: number; query?: string }): Promise<ServerMessage> {
    const limit = Math.max(1, Math.min(input.limit ?? 20, 50));
    const offset = Math.max(0, input.offset ?? 0);

    if (!this.composio) {
      return {
        type: "composio_integrations",
        configured: false,
        integrations: [],
        total: 0,
        hasMore: false,
        offset,
        limit,
        error: "Set COMPOSIO_API_KEY in the Detach runtime environment to enable built-in Composio integrations.",
      };
    }

    const { session } = await this.ensureManagementSession(input.userId);
    const response = await session.toolkits({
      limit: offset + limit,
      search: input.query?.trim() || undefined,
    });
    const items = response.items.slice(offset, offset + limit).map(toolkitToIntegration);

    return {
      type: "composio_integrations",
      configured: true,
      integrations: items,
      total: estimateTotal(offset, items.length, limit, response),
      hasMore: Boolean(response.cursor) || response.items.length > offset + items.length,
      offset,
      limit,
    };
  }

  async connectToolkit(input: { toolkit: string; userId?: string; callbackUrl?: string }): Promise<{
    messages: ServerMessage[];
    pending?: Promise<ServerMessage[]>;
  }> {
    const { session } = await this.ensureManagementSession(input.userId);

    if (input.toolkit === "composio-mcp") {
      const connectedToolkits = await this.connectedToolkits(input.userId);
      if (connectedToolkits.length === 0) {
        throw new Error("Connect a Composio toolkit before adding Composio MCP to a chat.");
      }
      const { mcpServer } = await this.ensureDirectMCPSession(input.userId, connectedToolkits);
      return {
        messages: [
          { type: "mcp_server_added", server: mcpServer, status: statusForServer(mcpServer) },
          { type: "composio_connected", toolkit: input.toolkit, connectionId: mcpServer.id, connectionStatus: "ACTIVE" },
        ],
      };
    }

    const request = await session.authorize(input.toolkit, {
      callbackUrl: input.callbackUrl?.trim() || Bun.env.COMPOSIO_CALLBACK_URL?.trim() || undefined,
    });

    if (request.redirectUrl) {
      return {
        messages: [
          {
            type: "composio_auth_url",
            url: request.redirectUrl,
            toolkit: input.toolkit,
            connectionId: request.id,
          },
        ],
        pending: request.waitForConnection(composioAuthTimeoutMs()).then(async (account) => {
          const toolkit = account.toolkit?.slug ?? input.toolkit;
          const { mcpServer } = await this.ensureDirectMCPSession(input.userId, [toolkit]);
          return [
            { type: "mcp_server_added", server: mcpServer, status: statusForServer(mcpServer) },
            {
              type: "composio_connected",
              toolkit,
              connectionId: account.id,
              connectionStatus: account.status,
            },
          ];
        }),
      };
    }

    const { mcpServer } = await this.ensureDirectMCPSession(input.userId, [input.toolkit]);
    return {
      messages: [
        { type: "mcp_server_added", server: mcpServer, status: statusForServer(mcpServer) },
        {
          type: "composio_connected",
          toolkit: input.toolkit,
          connectionId: request.id,
          connectionStatus: request.status ?? "ACTIVE",
        },
      ],
    };
  }

  async listConnections(input: { userId?: string }): Promise<ComposioConnection[]> {
    if (!this.composio) return [];
    const connections = await this.connectedConnections(input.userId);

    const connectedToolkits = connections
      .filter((connection) => connection.status === "ACTIVE")
      .map((connection) => connection.toolkit);
    if (connectedToolkits.length > 0) {
      await this.ensureDirectMCPSession(input.userId, connectedToolkits);
    }

    return connections;
  }

  async disconnect(connectionId: string) {
    if (!this.composio) return;
    await this.composio.connectedAccounts.delete(connectionId);
  }

  private async connectedToolkits(userId?: string) {
    return (await this.connectedConnections(userId))
      .filter((connection) => connection.status === "ACTIVE")
      .map((connection) => connection.toolkit);
  }

  private async connectedConnections(userId?: string): Promise<ComposioConnection[]> {
    const { session } = await this.ensureManagementSession(userId);
    const response = await session.toolkits({ limit: 100, isConnected: true });
    return response.items
      .filter((item) => item.connection?.connectedAccount?.id)
      .map((item) => ({
        id: item.connection?.connectedAccount?.id ?? item.slug,
        toolkit: item.slug,
        status: item.connection?.connectedAccount?.status ?? (item.connection?.isActive ? "ACTIVE" : "UNKNOWN"),
        connectedAt: new Date().toISOString(),
      }));
  }

  private async ensureManagementSession(userId?: string) {
    if (!this.composio) {
      throw new Error("Set COMPOSIO_API_KEY in the Detach runtime environment to enable Composio.");
    }

    const resolvedUserId = this.sessionStore.resolveUserId(userId);
    const storageKey = composioSessionStorageKey(resolvedUserId, "management");
    const existing = this.sessionStore.get(storageKey);
    let session: ComposioSession | undefined;

    if (existing) {
      try {
        session = await this.composio.sessions.use(existing.sessionId, { mcp: true }) as unknown as ComposioSession;
      } catch {
        session = undefined;
      }
    }

    if (!session) {
      session = await this.composio.sessions.create(resolvedUserId, {
        mcp: true,
        manageConnections: {
          enable: true,
          callbackUrl: Bun.env.COMPOSIO_CALLBACK_URL?.trim() || undefined,
          waitForConnections: false,
        },
      }) as unknown as ComposioSession;
    }

    if (!session.mcp?.url) {
      throw new Error("Composio did not return an MCP endpoint for this session.");
    }

    this.sessionStore.upsert({
      userId: storageKey,
      sessionId: session.sessionId,
      mcpUrl: session.mcp.url,
      headers: session.mcp.headers,
    });

    return { userId: resolvedUserId, session };
  }

  private async ensureDirectMCPSession(userId: string | undefined, toolkits: string[]) {
    if (!this.composio) {
      throw new Error("Set COMPOSIO_API_KEY in the Detach runtime environment to enable Composio.");
    }

    const resolvedUserId = this.sessionStore.resolveUserId(userId);
    const storageKey = composioSessionStorageKey(resolvedUserId, "mcp");
    const normalizedToolkits = normalizeToolkits(toolkits);
    const existing = this.sessionStore.get(storageKey);
    const existingMCPServer = existing?.mcpServerId ? this.mcpServers.get(existing.mcpServerId) : undefined;
    const existingToolkits = composioToolkitsFromServer(existingMCPServer);
    let session: ComposioSession | undefined;

    if (existing && sameToolkits(existingToolkits, normalizedToolkits)) {
      try {
        session = await this.composio.sessions.use(existing.sessionId, { mcp: true }) as unknown as ComposioSession;
      } catch {
        session = undefined;
      }
    }

    if (!session) {
      session = await this.composio.sessions.create(resolvedUserId, {
        mcp: true,
        sessionPreset: SessionPreset.DIRECT_TOOLS,
        ...(normalizedToolkits.length > 0 ? { toolkits: normalizedToolkits } : {}),
      }) as unknown as ComposioSession;
    }

    if (!session.mcp?.url) {
      throw new Error("Composio did not return an MCP endpoint for this session.");
    }

    const mcpServer = this.upsertMCPServer(existing?.mcpServerId, session, normalizedToolkits);
    this.sessionStore.upsert({
      userId: storageKey,
      sessionId: session.sessionId,
      mcpServerId: mcpServer.id,
      mcpUrl: session.mcp.url,
      headers: session.mcp.headers,
    });

    return { userId: resolvedUserId, session, mcpServer };
  }

  private upsertMCPServer(preferredId: string | undefined, session: ComposioSession, toolkits: string[]): MCPServerConfig {
    const existing =
      (preferredId ? this.mcpServers.get(preferredId) : undefined) ??
      this.mcpServers.list().find((server) => server.name === "Composio MCP");
    const input = {
      name: "Composio MCP",
      transport: session.mcp.type === "sse" ? "sse" as const : "http" as const,
      url: session.mcp.url,
      headers: session.mcp.headers,
      enabled: true,
      approvalPolicy: "auto-approve" as const,
      toolNames: composioToolMarkers(toolkits),
    };

    return existing ? this.mcpServers.update(existing.id, input) ?? existing : this.mcpServers.add(input);
  }
}

function toolkitToIntegration(toolkit: ToolkitState): ComposioIntegration {
  const account = toolkit.connection?.connectedAccount;
  const connected = Boolean(toolkit.isNoAuth || toolkit.connection?.isActive);
  return {
    id: toolkit.slug,
    name: toolkit.name,
    description: toolkit.isNoAuth
      ? "No authentication required"
      : connected
        ? `Connected${account?.status ? ` (${account.status})` : ""}`
        : "Connect through Composio",
    icon: toolkit.logo || "puzzlepiece.extension",
    connected,
    connectionId: account?.id,
  };
}

function estimateTotal(offset: number, count: number, limit: number, response: ToolkitListResponse) {
  if (response.totalPages && response.totalPages > 0) return response.totalPages * limit;
  return offset + count + (response.cursor ? limit : 0);
}

function composioAuthTimeoutMs() {
  const configured = Number(Bun.env.DETACH_COMPOSIO_AUTH_TIMEOUT_MS || 180_000);
  return Number.isFinite(configured) && configured > 0 ? configured : 180_000;
}

function composioSessionStorageKey(userId: string, purpose: "management" | "mcp") {
  return `${userId}::${purpose}`;
}

function normalizeToolkits(toolkits: string[]) {
  return [...new Set(toolkits.map((toolkit) => toolkit.trim().toLowerCase()).filter(Boolean))].sort();
}

function sameToolkits(left: string[], right: string[]) {
  if (left.length !== right.length) return false;
  return left.every((value, index) => value === right[index]);
}

function composioToolMarkers(toolkits: string[]) {
  return ["composio-direct-tools-v1", ...normalizeToolkits(toolkits).map((toolkit) => `composio-toolkit:${toolkit}`)];
}

function composioToolkitsFromServer(server?: MCPServerConfig) {
  return normalizeToolkits(
    (server?.toolNames ?? [])
      .map((name) => name.startsWith("composio-toolkit:") ? name.slice("composio-toolkit:".length) : "")
      .filter(Boolean)
  );
}
