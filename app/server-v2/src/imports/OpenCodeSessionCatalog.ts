import { Database } from "bun:sqlite";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { MAX_DISCOVERY, MAX_TRANSCRIPT_BYTES } from "./Transcript";

export interface OpenCodeCatalog { sessions: unknown[]; complete: boolean }

/** `opencode session list` is project-scoped. Read only native metadata across projects. */
export function readOpenCodeSessionCatalog(path = join(Bun.env.XDG_DATA_HOME || join(homedir(), ".local", "share"), "opencode", "opencode.db")): OpenCodeCatalog | undefined {
  if (!existsSync(path)) return undefined;
  let db: Database | undefined;
  try {
    db = new Database(path, { readonly: true });
    const columns = new Set(db.query<{ name: string }, []>("PRAGMA table_info(session)").all().map((row) => row.name));
    if (!["id", "directory", "title", "time_created", "time_updated", "parent_id"].every((name) => columns.has(name))) return undefined;
    const archived = columns.has("time_archived") ? "time_archived" : "NULL AS time_archived";
    const rows = db.query<{ id: string; directory: string; title: string; time_created: number; time_updated: number; time_archived: number | null }, [number]>(
      `SELECT id, directory, title, time_created, time_updated, ${archived} FROM session
       WHERE parent_id IS NULL ORDER BY time_updated DESC, id LIMIT ?`).all(MAX_DISCOVERY + 1);
    return { sessions: rows.slice(0, MAX_DISCOVERY).map((row) => ({ id: row.id, directory: row.directory, title: row.title,
      time: { created: row.time_created, updated: row.time_updated, archived: row.time_archived } })), complete: rows.length <= MAX_DISCOVERY };
  } catch { return undefined; } // Unsupported native schema falls back without claiming an exhaustive list.
  finally { db?.close(); }
}

/** Read a single provider-owned transcript without piping screenshots through a CLI JSON export. */
export function readOpenCodeSessionTranscript(id: string, path = join(Bun.env.XDG_DATA_HOME || join(homedir(), ".local", "share"), "opencode", "opencode.db")): unknown | undefined {
  if (!/^ses_[a-zA-Z0-9_-]+$/.test(id) || !existsSync(path)) return undefined;
  let db: Database | undefined;
  try {
    db = new Database(path, { readonly: true });
    const supported = ["session", "message", "part"].every((table) => db!.query("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?").get(table));
    if (!supported || !db.query("SELECT 1 FROM session WHERE id=?").get(id)) return undefined;
    const rows = db.query<{ id: string; data: string }, [string]>("SELECT id,data FROM message WHERE session_id=? ORDER BY time_created,id LIMIT 10001").all(id);
    const parts = db.query<{ message_id: string; data: string }, [string]>("SELECT message_id,data FROM part WHERE session_id=? ORDER BY time_created,id LIMIT 50001").all(id);
    if (rows.length > 10000 || parts.length > 50000 || [...rows, ...parts].reduce((size, row) => size + Buffer.byteLength(row.data), 0) > MAX_TRANSCRIPT_BYTES) {
      throw new OpenCodeTranscriptLimitError();
    }
    const byMessage = new Map<string, unknown[]>();
    for (const part of parts) {
      const value = byMessage.get(part.message_id) ?? [];
      value.push(JSON.parse(part.data)); byMessage.set(part.message_id, value);
    }
    return { messages: rows.map((row) => ({ info: { ...JSON.parse(row.data), id: row.id }, parts: byMessage.get(row.id) ?? [] })) };
  } catch (error) {
    if (error instanceof OpenCodeTranscriptLimitError) throw error;
    return undefined;
  } finally { db?.close(); }
}

class OpenCodeTranscriptLimitError extends Error {
  constructor() { super("This OpenCode conversation is too large to read safely."); }
}
