import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { defaultDatabasePath } from "./databasePath";

const schema = `
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS composio_sessions (
  user_id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  mcp_server_id TEXT,
  mcp_url TEXT NOT NULL,
  headers TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
`;

export interface ComposioSessionRecord {
  userId: string;
  sessionId: string;
  mcpServerId?: string;
  mcpUrl: string;
  headers?: Record<string, string>;
  created_at: number;
  updated_at: number;
}

interface ComposioSessionRow {
  user_id: string;
  session_id: string;
  mcp_server_id: string | null;
  mcp_url: string;
  headers: string | null;
  created_at: number;
  updated_at: number;
}

interface SettingRow {
  value: string;
}

export class SqliteComposioSessions {
  private readonly db: Database;

  constructor(dbPath = defaultDatabasePath()) {
    mkdirSync(dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath, { create: true });
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec("PRAGMA synchronous = NORMAL;");
    this.db.exec("PRAGMA busy_timeout = 5000;");
    this.db.exec(schema);
  }

  resolveUserId(input?: string) {
    const explicit = input?.trim() || Bun.env.DETACH_USER_ID?.trim();
    if (explicit) return explicit;

    const existing = this.db.query<SettingRow, [string]>("SELECT value FROM app_settings WHERE key = ?").get("local_user_id");
    if (existing?.value) return existing.value;

    const generated = `detach_local_${crypto.randomUUID()}`;
    this.db.run(
      "INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?)",
      ["local_user_id", generated, Date.now()]
    );
    return generated;
  }

  get(userId: string) {
    const row = this.db
      .query<ComposioSessionRow, [string]>(
        "SELECT user_id, session_id, mcp_server_id, mcp_url, headers, created_at, updated_at FROM composio_sessions WHERE user_id = ?"
      )
      .get(userId);

    return row ? rowToRecord(row) : undefined;
  }

  upsert(input: {
    userId: string;
    sessionId: string;
    mcpServerId?: string;
    mcpUrl: string;
    headers?: Record<string, string>;
  }) {
    const now = Date.now();
    const existing = this.get(input.userId);
    const createdAt = existing?.created_at ?? now;

    this.db.run(
      `INSERT INTO composio_sessions (user_id, session_id, mcp_server_id, mcp_url, headers, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET
         session_id = excluded.session_id,
         mcp_server_id = excluded.mcp_server_id,
         mcp_url = excluded.mcp_url,
         headers = excluded.headers,
         updated_at = excluded.updated_at`,
      [
        input.userId,
        input.sessionId,
        input.mcpServerId ?? null,
        input.mcpUrl,
        input.headers ? JSON.stringify(input.headers) : null,
        createdAt,
        now,
      ]
    );

    return {
      userId: input.userId,
      sessionId: input.sessionId,
      mcpServerId: input.mcpServerId,
      mcpUrl: input.mcpUrl,
      headers: input.headers,
      created_at: createdAt,
      updated_at: now,
    } satisfies ComposioSessionRecord;
  }
}

function rowToRecord(row: ComposioSessionRow): ComposioSessionRecord {
  return {
    userId: row.user_id,
    sessionId: row.session_id,
    mcpServerId: row.mcp_server_id ?? undefined,
    mcpUrl: row.mcp_url,
    headers: parseStringMap(row.headers),
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
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
