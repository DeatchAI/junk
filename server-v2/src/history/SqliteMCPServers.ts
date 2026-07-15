import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { MCPServerConfig, MCPServerStatus } from "../protocol/messages";
import { defaultDatabasePath } from "./databasePath";

const schema = `
CREATE TABLE IF NOT EXISTS mcp_servers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  transport TEXT NOT NULL CHECK(transport IN ('stdio', 'sse', 'http')),
  command TEXT,
  args TEXT,
  url TEXT,
  headers TEXT,
  env TEXT,
  enabled INTEGER DEFAULT 1,
  approval_policy TEXT CHECK(approval_policy IN ('prompt', 'auto-approve')),
  tool_names TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
`;

interface MCPServerRow {
  id: string;
  name: string;
  transport: "stdio" | "sse" | "http";
  command: string | null;
  args: string | null;
  url: string | null;
  headers: string | null;
  env: string | null;
  enabled: number;
  approval_policy: "prompt" | "auto-approve" | null;
  tool_names: string | null;
  created_at: number;
  updated_at: number;
}

export class SqliteMCPServers {
  private readonly db: Database;

  constructor(dbPath = defaultDatabasePath()) {
    mkdirSync(dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath, { create: true });
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec("PRAGMA synchronous = NORMAL;");
    this.db.exec("PRAGMA busy_timeout = 5000;");
    this.db.exec(schema);
    this.migrate();
  }

  list() {
    return this.db
      .query<MCPServerRow, []>(
        "SELECT id, name, transport, command, args, url, headers, env, enabled, approval_policy, tool_names, created_at, updated_at FROM mcp_servers ORDER BY name ASC"
      )
      .all()
      .map(rowToConfig);
  }

  listEnabled() {
    return this.list().filter((server) => server.enabled);
  }

  listWithStatus() {
    return this.list().map((server) => ({
      ...server,
      status: statusForServer(server),
    }));
  }

  add(input: {
    name: string;
    transport: "stdio" | "sse" | "http";
    command?: string;
    args?: string[];
    url?: string;
    headers?: Record<string, string>;
    env?: Record<string, string>;
    enabled?: boolean;
    approvalPolicy?: "prompt" | "auto-approve";
    toolNames?: string[];
  }) {
    const now = Date.now();
    const id = generateId("mcp");
    const enabled = input.enabled ?? true;

    this.db.run(
      `INSERT INTO mcp_servers (id, name, transport, command, args, url, headers, env, enabled, approval_policy, tool_names, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        id,
        input.name,
        input.transport,
        input.command ?? null,
        input.args ? JSON.stringify(input.args) : null,
        input.url ?? null,
        input.headers ? JSON.stringify(input.headers) : null,
        input.env ? JSON.stringify(input.env) : null,
        enabled ? 1 : 0,
        input.approvalPolicy ?? null,
        input.toolNames ? JSON.stringify(input.toolNames) : null,
        now,
        now,
      ]
    );

    return {
      id,
      name: input.name,
      transport: input.transport,
      command: input.command,
      args: input.args,
      url: input.url,
      headers: input.headers,
      env: input.env,
      enabled,
      approvalPolicy: input.approvalPolicy,
      toolNames: input.toolNames,
      created_at: now,
      updated_at: now,
    } satisfies MCPServerConfig;
  }

  get(id: string) {
    const row = this.db
      .query<MCPServerRow, [string]>(
        "SELECT id, name, transport, command, args, url, headers, env, enabled, approval_policy, tool_names, created_at, updated_at FROM mcp_servers WHERE id = ?"
      )
      .get(id);

    return row ? rowToConfig(row) : undefined;
  }

  update(id: string, input: Partial<Omit<MCPServerConfig, "id" | "created_at" | "updated_at">>) {
    const current = this.get(id);
    if (!current) return undefined;

    const next: MCPServerConfig = {
      ...current,
      ...input,
      updated_at: Date.now(),
    };

    this.db.run(
      `UPDATE mcp_servers
       SET name = ?, transport = ?, command = ?, args = ?, url = ?, headers = ?, env = ?, enabled = ?, approval_policy = ?, tool_names = ?, updated_at = ?
       WHERE id = ?`,
      [
        next.name,
        next.transport,
        next.command ?? null,
        next.args ? JSON.stringify(next.args) : null,
        next.url ?? null,
        next.headers ? JSON.stringify(next.headers) : null,
        next.env ? JSON.stringify(next.env) : null,
        next.enabled ? 1 : 0,
        next.approvalPolicy ?? null,
        next.toolNames ? JSON.stringify(next.toolNames) : null,
        next.updated_at,
        id,
      ]
    );

    return next;
  }

  delete(id: string) {
    const result = this.db.run("DELETE FROM mcp_servers WHERE id = ?", [id]);
    return result.changes > 0;
  }

  private migrate() {
    const columns = new Set(
      this.db
        .query<{ name: string }, []>("PRAGMA table_info(mcp_servers)")
        .all()
        .map((column) => column.name)
    );

    if (!columns.has("approval_policy")) {
      this.db.exec("ALTER TABLE mcp_servers ADD COLUMN approval_policy TEXT CHECK(approval_policy IN ('prompt', 'auto-approve'));");
    }

    if (!columns.has("tool_names")) {
      this.db.exec("ALTER TABLE mcp_servers ADD COLUMN tool_names TEXT;");
    }

    this.db.run(
      "UPDATE mcp_servers SET approval_policy = 'auto-approve' WHERE name = ? AND approval_policy IS NULL",
      ["Composio MCP"]
    );
  }
}

export function statusForServer(server: MCPServerConfig): MCPServerStatus {
  if (!server.enabled) {
    return {
      id: server.id,
      name: server.name,
      connected: false,
      tools: [],
    };
  }

  return {
    id: server.id,
    name: server.name,
    connected: true,
    tools: [],
  };
}

function rowToConfig(row: MCPServerRow): MCPServerConfig {
  return {
    id: row.id,
    name: row.name,
    transport: row.transport,
    command: row.command ?? undefined,
    args: parseStringArray(row.args),
    url: row.url ?? undefined,
    headers: parseStringMap(row.headers),
    env: parseStringMap(row.env),
    enabled: row.enabled === 1,
    approvalPolicy: row.approval_policy ?? undefined,
    toolNames: parseStringArray(row.tool_names),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

function parseStringArray(value: string | null) {
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === "string") : undefined;
  } catch {
    return undefined;
  }
}

function parseStringMap(value: string | null) {
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(value);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return undefined;
    return Object.fromEntries(
      Object.entries(parsed).filter((entry): entry is [string, string] => typeof entry[1] === "string")
    );
  } catch {
    return undefined;
  }
}

function generateId(prefix: string) {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}
