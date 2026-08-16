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

interface HostedControlPlane {
  endpoint: string;
  accessToken: string;
}

interface BrokerSession {
  id: string;
  mode: "manage" | "execute";
  mcp: {
    type?: "http" | "sse";
    url: string;
    headers?: Record<string, string>;
  };
}

interface BrokerIntegrationResponse {
  items?: ToolkitState[];
  total?: number;
  hasMore?: boolean;
  offset?: number;
  limit?: number;
}

interface BrokerConnectionsResponse {
  items?: ToolkitState[];
}

interface BrokerConnectResponse {
  connection?: {
    id?: string;
    redirectUrl?: string | null;
    status?: string | null;
  };
}

interface BrokerSessionResponse {
  session?: {
    id?: string;
    mode?: "manage" | "execute";
    mcp?: {
      type?: "http" | "sse";
      url?: string;
      headers?: Record<string, string>;
    };
  };
}

interface BrokerError extends Error {
  status?: number;
}

interface ComposioSessionManagerOptions {
  fetcher?: typeof fetch;
}

export class ComposioSessionManager {
  private readonly sessionStore: SqliteComposioSessions;
  private readonly mcpServers: SqliteMCPServers;
  private readonly fetcher: typeof fetch;
  private controlPlane?: HostedControlPlane;
  private paidAccess = false;
  private lastAccessCheckAt = 0;

  constructor(
    mcpServers: SqliteMCPServers,
    sessionStore = new SqliteComposioSessions(),
    options: ComposioSessionManagerOptions = {},
  ) {
    this.mcpServers = mcpServers;
    this.sessionStore = sessionStore;
    this.fetcher = options.fetcher ?? fetch;
  }

  /**
   * The Composio project key stays on the hosted control plane. The bundled
   * runtime receives only the signed-in user's session credentials and uses
   * them to connect directly to Composio's MCP endpoint.
   */
  configureHostedControlPlane(input: { endpoint?: string; accessToken?: string }) {
    const endpoint = normalizeControlPlaneURL(input.endpoint);
    const accessToken = input.accessToken?.trim();
    this.controlPlane = endpoint && accessToken ? { endpoint, accessToken } : undefined;
    this.paidAccess = false;
    this.lastAccessCheckAt = 0;

    if (!this.controlPlane) {
      this.disableComposioServer();
    }
  }

  isConfigured() {
    return Boolean(this.controlPlane);
  }

  isAccessAllowed() {
    return this.paidAccess;
  }

  async refreshAccess(options: { force?: boolean } = {}): Promise<boolean> {
    if (!this.controlPlane) {
      this.paidAccess = false;
      this.lastAccessCheckAt = 0;
      this.disableComposioServer();
      return false;
    }

    if (!options.force && this.paidAccess && Date.now() - this.lastAccessCheckAt < 60_000) {
      return true;
    }

    try {
      const response = await this.request<{ enabled?: boolean }>({ action: "access" });
      this.paidAccess = response.enabled === true;
      this.lastAccessCheckAt = Date.now();
      if (!this.paidAccess) this.disableComposioServer();
      return this.paidAccess;
    } catch {
      this.paidAccess = false;
      this.lastAccessCheckAt = Date.now();
      this.disableComposioServer();
      return false;
    }
  }

  async listIntegrations(input: { userId?: string; limit?: number; offset?: number; query?: string }): Promise<ServerMessage> {
    const limit = Math.max(1, input.limit ?? 20);
    const offset = Math.max(0, input.offset ?? 0);

    try {
      await this.ensurePaidAccess();
    } catch (error) {
      return this.unconfiguredIntegrations(limit, offset, errorMessage(error));
    }

    const userId = requiredUserId(input.userId);
    const response = await this.request<BrokerIntegrationResponse>({
      action: "integrations",
      userId,
      limit,
      offset,
      query: input.query?.trim() || undefined,
    });
    const integrations = (response.items ?? []).map(toolkitToIntegration);

    return {
      type: "composio_integrations",
      configured: true,
      integrations,
      total: response.total ?? integrations.length,
      hasMore: response.hasMore ?? false,
      offset,
      limit,
    };
  }

  async connectToolkit(input: { toolkit: string; userId?: string; callbackUrl?: string }): Promise<{
    messages: ServerMessage[];
    pending?: Promise<ServerMessage[]>;
  }> {
    await this.ensurePaidAccess();
    const userId = requiredUserId(input.userId);

    if (input.toolkit === "composio-mcp") {
      const connections = await this.fetchConnections();
      const connectedToolkits = activeToolkits(connections);
      if (connectedToolkits.length === 0) {
        throw new Error("Connect a Composio toolkit before adding Composio MCP to a chat.");
      }
      return { messages: await this.mcpServerMessages(userId, connectedToolkits, input.toolkit, "ACTIVE") };
    }

    const response = await this.request<BrokerConnectResponse>({
      action: "connect",
      toolkit: input.toolkit,
      callbackUrl: input.callbackUrl?.trim() || undefined,
    });
    const connection = response.connection;
    if (!connection?.id) {
      throw new Error("Composio did not return a connection request.");
    }

    if (connection.redirectUrl) {
      return {
        messages: [{
          type: "composio_auth_url",
          url: connection.redirectUrl,
          toolkit: input.toolkit,
          connectionId: connection.id,
        }],
        pending: this.waitForConnection({
          userId,
          toolkit: input.toolkit,
          connectionId: connection.id,
        }),
      };
    }

    return {
      messages: await this.mcpServerMessages(
        userId,
        activeToolkits(await this.fetchConnections()),
        input.toolkit,
        connection.status ?? "ACTIVE",
        connection.id,
      ),
    };
  }

  async listConnections(input: { userId?: string }): Promise<ComposioConnection[]> {
    await this.ensurePaidAccess();
    const userId = requiredUserId(input.userId);
    const connections = await this.fetchConnections();
    const connectedToolkits = activeToolkits(connections);
    if (connectedToolkits.length > 0) {
      await this.ensureDirectMCPSession(userId, connectedToolkits);
    }
    return connections;
  }

  async disconnect(connectionId: string, userId?: string) {
    await this.ensurePaidAccess();
    const resolvedUserId = requiredUserId(userId);
    await this.request({
      action: "disconnect",
      connectionId,
    });

    const connections = await this.fetchConnections();
    const connectedToolkits = activeToolkits(connections);
    if (connectedToolkits.length > 0) {
      await this.ensureDirectMCPSession(resolvedUserId, connectedToolkits);
    } else {
      this.disableComposioServer();
    }
  }

  private async ensurePaidAccess() {
    if (!this.controlPlane) {
      throw new Error("Sign in to Detach to use Composio integrations.");
    }
    if (!(await this.refreshAccess())) {
      throw new Error("Composio integrations require an active paid Detach plan.");
    }
  }

  private async fetchConnections(): Promise<ComposioConnection[]> {
    const response = await this.request<BrokerConnectionsResponse>({ action: "connections" });
    return (response.items ?? []).flatMap((item) => {
      const account = item.connection?.connectedAccount;
      if (!account?.id) return [];
      return [{
        id: account.id,
        toolkit: item.slug,
        status: account.status ?? (item.connection?.isActive ? "ACTIVE" : "UNKNOWN"),
        connectedAt: new Date().toISOString(),
      } satisfies ComposioConnection];
    });
  }

  private async waitForConnection(input: {
    userId: string;
    toolkit: string;
    connectionId: string;
  }): Promise<ServerMessage[]> {
    const deadline = Date.now() + composioAuthTimeoutMs();
    while (Date.now() < deadline) {
      const connection = (await this.fetchConnections()).find((item) => item.id === input.connectionId);
      if (connection && isActiveStatus(connection.status)) {
        return this.mcpServerMessages(
          input.userId,
          activeToolkits(await this.fetchConnections()),
          input.toolkit,
          connection.status,
          connection.id,
        );
      }
      if (connection && ["EXPIRED", "FAILED", "REVOKED", "ERROR"].includes(connection.status.toUpperCase())) {
        throw new Error(`Composio connection for ${input.toolkit} did not complete (${connection.status}).`);
      }
      await delay(2_000);
    }

    throw new Error(`Timed out waiting for ${input.toolkit} to connect through Composio.`);
  }

  private async mcpServerMessages(
    userId: string,
    connectedToolkits: string[],
    toolkit: string,
    status: string,
    connectionId?: string,
  ): Promise<ServerMessage[]> {
    const sessionToolkits = connectedToolkits.length > 0 ? connectedToolkits : [toolkit];
    const { mcpServer } = await this.ensureDirectMCPSession(userId, sessionToolkits);
    return [
      { type: "mcp_server_added", server: mcpServer, status: statusForServer(mcpServer) },
      {
        type: "composio_connected",
        toolkit,
        connectionId: connectionId ?? mcpServer.id,
        connectionStatus: status,
      },
    ];
  }

  private async ensureDirectMCPSession(userId: string, toolkits: string[]) {
    const normalizedToolkits = normalizeToolkits(toolkits);
    const storageKey = composioSessionStorageKey(userId, "mcp");
    const existing = this.sessionStore.get(storageKey);

    const response = await this.request<BrokerSessionResponse>({
      action: "session",
      mode: "execute",
      toolkits: normalizedToolkits,
    });
    const session = parseBrokerSession(response, "execute");
    const mcpServer = this.upsertMCPServer(existing?.mcpServerId, session, normalizedToolkits);

    this.sessionStore.upsert({
      userId: storageKey,
      sessionId: session.id,
      mcpServerId: mcpServer.id,
      mcpUrl: session.mcp.url,
      headers: session.mcp.headers,
    });

    return { session, mcpServer };
  }

  private async request<T = Record<string, unknown>>(body: Record<string, unknown>): Promise<T> {
    const controlPlane = this.controlPlane;
    if (!controlPlane) {
      throw new Error("Sign in to Detach to use Composio integrations.");
    }

    const response = await this.fetcher(`${controlPlane.endpoint}/api/composio-session`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${controlPlane.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
    const payload = await response.json().catch(() => undefined) as unknown;
    if (!response.ok) {
      const message = errorMessageFromPayload(payload) || `Composio control plane failed with HTTP ${response.status}.`;
      const error = new Error(message) as BrokerError;
      error.status = response.status;
      if (response.status === 401 || response.status === 403) {
        this.paidAccess = false;
        this.disableComposioServer();
      }
      throw error;
    }

    return payload as T;
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

  private disableComposioServer() {
    const server = this.mcpServers.list().find((item) => item.name === "Composio MCP");
    if (server?.enabled) {
      this.mcpServers.update(server.id, { enabled: false });
    }
  }

  private upsertMCPServer(preferredId: string | undefined, session: BrokerSession, toolkits: string[]): MCPServerConfig {
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

function parseBrokerSession(value: BrokerSessionResponse, expectedMode: "manage" | "execute"): BrokerSession {
  const session = value.session;
  if (!session) {
    throw new Error("Composio control plane returned an invalid MCP session.");
  }
  const id = session?.id?.trim() ?? "";
  const url = session?.mcp?.url?.trim() ?? "";
  const mode = session?.mode ?? expectedMode;
  if (!id || !url || mode !== expectedMode) {
    throw new Error("Composio control plane returned an invalid MCP session.");
  }

  let parsedURL: URL;
  try {
    parsedURL = new URL(url);
  } catch {
    throw new Error("Composio control plane returned an invalid MCP URL.");
  }
  if (parsedURL.protocol !== "https:") {
    throw new Error("Composio control plane returned an insecure MCP URL.");
  }

  const headers = session.mcp?.headers
    ? Object.fromEntries(Object.entries(session.mcp.headers).filter((entry): entry is [string, string] => typeof entry[1] === "string"))
    : undefined;

  return {
    id,
    mode,
    mcp: {
      type: session.mcp?.type,
      url,
      headers,
    },
  };
}

function errorMessageFromPayload(payload: unknown) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return undefined;
  const error = (payload as Record<string, unknown>).error;
  if (!error || typeof error !== "object" || Array.isArray(error)) return undefined;
  const message = (error as Record<string, unknown>).message;
  return typeof message === "string" && message.trim() ? message : undefined;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Composio integrations are unavailable.";
}

function requiredUserId(userId?: string) {
  const resolved = userId?.trim();
  if (!resolved) throw new Error("Sign in to Detach before using Composio integrations.");
  return resolved;
}

function activeToolkits(connections: ComposioConnection[]) {
  return normalizeToolkits(
    connections.filter((connection) => isActiveStatus(connection.status)).map((connection) => connection.toolkit),
  );
}

function isActiveStatus(status: string) {
  return status.toUpperCase() === "ACTIVE";
}

function normalizeControlPlaneURL(value: string | undefined) {
  const candidate = value?.trim();
  if (!candidate) return undefined;

  try {
    const url = new URL(candidate);
    const isLocalDevelopment = url.protocol === "http:"
      && (url.hostname === "127.0.0.1" || url.hostname === "localhost");
    if (url.protocol !== "https:" && !isLocalDevelopment) return undefined;
    return url.toString().replace(/\/$/, "");
  } catch {
    return undefined;
  }
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

function composioToolMarkers(toolkits: string[]) {
  return ["composio-direct-tools-v1", ...normalizeToolkits(toolkits).map((toolkit) => `composio-toolkit:${toolkit}`)];
}

function delay(milliseconds: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, milliseconds));
}
