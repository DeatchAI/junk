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

interface HostedControlPlaneConfig {
  endpoint: string;
  accessToken: string;
}

interface HostedSessionResponse {
  session?: {
    id?: string;
    mcp?: {
      type?: "http" | "sse";
      url?: string;
      headers?: Record<string, string>;
    };
  };
}

interface HostedToolkitResponse {
  items?: ToolkitState[];
  cursor?: string;
}

interface HostedConnectionResponse {
  connection?: {
    id?: string;
    redirectUrl?: string | null;
    status?: string | null;
  };
}

export class ComposioSessionManager {
  private readonly sessionStore: SqliteComposioSessions;
  private readonly mcpServers: SqliteMCPServers;
  private readonly composio?: Composio;
  private readonly hostedMode: boolean;
  private hostedControlPlane?: HostedControlPlaneConfig;

  constructor(mcpServers: SqliteMCPServers, sessionStore = new SqliteComposioSessions()) {
    this.mcpServers = mcpServers;
    this.sessionStore = sessionStore;
    this.hostedMode = Bun.env.DETACH_DISTRIBUTION_MODE?.trim().toLowerCase() === "hosted";

    // Development-only fallback. Production builds use the hosted control
    // plane, where the Detach-owned Composio key never reaches this runtime.
    const apiKey = Bun.env.COMPOSIO_API_KEY?.trim();
    if (!this.hostedMode && apiKey) {
      this.composio = new Composio({
        apiKey,
        allowTracking: false,
        disableVersionCheck: true,
        host: "detach-runtime",
      });
    }
  }

  isConfigured() {
    return this.hostedMode ? Boolean(this.hostedControlPlane) : Boolean(this.composio);
  }

  configureHostedControlPlane(input: { endpoint?: string; accessToken?: string }) {
    if (!this.hostedMode) return;

    const endpoint = input.endpoint?.trim();
    const accessToken = input.accessToken?.trim();
    if (!endpoint || !accessToken) {
      this.hostedControlPlane = undefined;
      return;
    }

    try {
      const url = new URL(endpoint);
      if (url.protocol !== "https:") throw new Error("Hosted control plane must use HTTPS.");
      this.hostedControlPlane = { endpoint: url.toString().replace(/\/$/, ""), accessToken };
    } catch {
      this.hostedControlPlane = undefined;
    }
  }

  async listIntegrations(input: { userId?: string; limit?: number; offset?: number; query?: string }): Promise<ServerMessage> {
    const limit = Math.max(1, Math.min(input.limit ?? 20, 50));
    const offset = Math.max(0, input.offset ?? 0);

    if (this.hostedMode) {
      if (!this.hostedControlPlane) return this.unconfiguredIntegrations(limit, offset, "Sign in to the hosted Detach app to enable Composio.");
      return this.listHostedIntegrations(input, limit, offset);
    }

    if (!this.composio) {
      return this.unconfiguredIntegrations(limit, offset, "Set COMPOSIO_API_KEY in the Detach runtime environment to enable built-in Composio integrations.");
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
    if (this.hostedMode) return this.connectHostedToolkit(input);
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
    if (this.hostedMode) {
      if (!this.hostedControlPlane) return [];
      const connections = await this.hostedConnections();
      const connectedToolkits = connections
        .filter((connection) => connection.status === "ACTIVE")
        .map((connection) => connection.toolkit);
      if (connectedToolkits.length > 0) await this.ensureDirectMCPSession(input.userId, connectedToolkits);
      return connections;
    }
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
    if (this.hostedMode) {
      if (!this.hostedControlPlane) return;
      await this.hostedRequest({ action: "disconnect", connectionId });
      return;
    }
    if (!this.composio) return;
    await this.composio.connectedAccounts.delete(connectionId);
  }

  private async connectedToolkits(userId?: string) {
    return (await this.connectedConnections(userId))
      .filter((connection) => connection.status === "ACTIVE")
      .map((connection) => connection.toolkit);
  }

  private async connectedConnections(userId?: string): Promise<ComposioConnection[]> {
    if (this.hostedMode) return this.hostedConnections();
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

  private unconfiguredIntegrations(limit: number, offset: number, error: string): ServerMessage {
    return {
      type: "composio_integrations",
      configured: false,
      integrations: [],
      total: 0,
      hasMore: false,
      offset,
      limit,
      error,
    };
  }

  private async listHostedIntegrations(
    input: { limit?: number; offset?: number; query?: string },
    limit: number,
    offset: number,
  ): Promise<ServerMessage> {
    const response = await this.hostedRequest({
      action: "integrations",
      limit: offset + limit,
      query: input.query?.trim() || undefined,
    }) as HostedToolkitResponse;
    const items = (response.items ?? []).slice(offset, offset + limit).map(toolkitToIntegration);
    return {
      type: "composio_integrations",
      configured: true,
      integrations: items,
      total: offset + items.length + (response.cursor ? limit : 0),
      hasMore: Boolean(response.cursor),
      offset,
      limit,
    };
  }

  private async connectHostedToolkit(input: { toolkit: string; userId?: string }): Promise<{
    messages: ServerMessage[];
    pending?: Promise<ServerMessage[]>;
  }> {
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

    const response = await this.hostedRequest({ action: "connect", toolkit: input.toolkit }) as HostedConnectionResponse;
    const connection = response.connection;
    if (!connection?.id) throw new Error("Hosted Composio did not return a connection request.");

    if (connection.redirectUrl) {
      return {
        messages: [{ type: "composio_auth_url", url: connection.redirectUrl, toolkit: input.toolkit, connectionId: connection.id }],
        pending: this.waitForHostedConnection(input.userId, input.toolkit).then(async (account) => {
          const { mcpServer } = await this.ensureDirectMCPSession(input.userId, [account.toolkit]);
          return [
            { type: "mcp_server_added", server: mcpServer, status: statusForServer(mcpServer) },
            { type: "composio_connected", toolkit: account.toolkit, connectionId: account.id, connectionStatus: account.status },
          ];
        }),
      };
    }

    const { mcpServer } = await this.ensureDirectMCPSession(input.userId, [input.toolkit]);
    return {
      messages: [
        { type: "mcp_server_added", server: mcpServer, status: statusForServer(mcpServer) },
        { type: "composio_connected", toolkit: input.toolkit, connectionId: connection.id, connectionStatus: connection.status ?? "ACTIVE" },
      ],
    };
  }

  private async hostedConnections(): Promise<ComposioConnection[]> {
    const response = await this.hostedRequest({ action: "connections" }) as HostedToolkitResponse;
    return (response.items ?? [])
      .filter((item) => item.connection?.connectedAccount?.id)
      .map((item) => ({
        id: item.connection?.connectedAccount?.id ?? item.slug,
        toolkit: item.slug,
        status: item.connection?.connectedAccount?.status ?? (item.connection?.isActive ? "ACTIVE" : "UNKNOWN"),
        connectedAt: new Date().toISOString(),
      }));
  }

  private async waitForHostedConnection(userId: string | undefined, toolkit: string): Promise<ComposioConnection> {
    const deadline = Date.now() + composioAuthTimeoutMs();
    while (Date.now() < deadline) {
      const connection = (await this.hostedConnections()).find(
        (candidate) => candidate.toolkit === toolkit && candidate.status === "ACTIVE",
      );
      if (connection) return connection;
      await new Promise((resolve) => setTimeout(resolve, 1_500));
    }
    throw new Error(`Timed out waiting for ${toolkit} to connect through hosted Composio.`);
  }

  private async ensureHostedDirectMCPSession(userId: string | undefined, toolkits: string[]) {
    const resolvedUserId = this.sessionStore.resolveUserId(userId);
    const storageKey = composioSessionStorageKey(resolvedUserId, "mcp");
    const normalizedToolkits = normalizeToolkits(toolkits);
    const existing = this.sessionStore.get(storageKey);
    const response = await this.hostedRequest({ action: "session", mode: "execute", toolkits: normalizedToolkits }) as HostedSessionResponse;
    const remote = response.session;
    if (!remote?.id || !remote.mcp?.url) {
      throw new Error("Hosted Composio did not return an MCP endpoint.");
    }

    const session = {
      sessionId: remote.id,
      mcp: {
        type: remote.mcp.type,
        url: remote.mcp.url,
        headers: remote.mcp.headers,
      },
    } as ComposioSession;
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

  private async hostedRequest(body: Record<string, unknown>): Promise<unknown> {
    const config = this.hostedControlPlane;
    if (!config) throw new Error("Sign in to the hosted Detach app to enable Composio.");

    const response = await fetch(`${config.endpoint}/api/composio-session`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.accessToken}`,
        "content-type": "application/json",
        "x-detach-distribution-mode": "hosted",
      },
      body: JSON.stringify(body),
    });
    const payload = await response.json().catch(() => undefined) as { error?: { message?: unknown } } | undefined;
    if (!response.ok) {
      const message = typeof payload?.error?.message === "string" ? payload.error.message : "Hosted Composio request failed.";
      throw new Error(message);
    }
    return payload;
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
    if (this.hostedMode) return this.ensureHostedDirectMCPSession(userId, toolkits);
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
