import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { defaultDataDir } from "../databasePath";
import type { AgentKind, Conversation, Message, SearchResult } from "../../protocol/messages";
import type { ExternalChat, ImportedMessage } from "../../imports/ImportTypes";
import { nativeConversationID } from "./NativeIdentity";
import { NativeBranches } from "../../branches/NativeBranches";
import { promptFingerprint, responseBranchPoint, type ConversationBranchState } from "../../branches/BranchTypes";

interface SessionRow { id: string; source_key: string; provider: AgentKind; json: string; indexed_version: number | null; unavailable: number }
const matchQuery = (query: string) => query.trim().split(/\s+/).filter(Boolean).map((word) => `"${word.replaceAll('"', '""')}"*`).join(" AND ");

/** Disposable mirror only. No message-creation API: provider histories remain authoritative. */
export class NativeHistoryIndex {
  private readonly db: Database;
  readonly branches: NativeBranches;
  constructor(path = join(defaultDataDir(), "provider-history-index.sqlite")) {
    mkdirSync(dirname(path), { recursive: true });
    this.db = new Database(path, { create: true });
    this.db.exec(`PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;
      CREATE TABLE IF NOT EXISTS provider_sessions (id TEXT PRIMARY KEY, source_key TEXT UNIQUE NOT NULL,
        provider TEXT NOT NULL, json TEXT NOT NULL, updated_at INTEGER NOT NULL, indexed_version INTEGER, unavailable INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS provider_messages (id TEXT PRIMARY KEY, conversation_id TEXT NOT NULL REFERENCES provider_sessions(id) ON DELETE CASCADE,
        role TEXT NOT NULL, content TEXT NOT NULL, created_at INTEGER NOT NULL, ordinal INTEGER NOT NULL);
      CREATE INDEX IF NOT EXISTS provider_messages_conversation ON provider_messages(conversation_id, ordinal);
      CREATE VIRTUAL TABLE IF NOT EXISTS provider_messages_fts USING fts5(content, content='provider_messages', content_rowid='rowid');
      CREATE TRIGGER IF NOT EXISTS native_message_insert AFTER INSERT ON provider_messages BEGIN
        INSERT INTO provider_messages_fts(rowid, content) VALUES (new.rowid, new.content); END;
      CREATE TRIGGER IF NOT EXISTS native_message_delete AFTER DELETE ON provider_messages BEGIN
        INSERT INTO provider_messages_fts(provider_messages_fts, rowid, content) VALUES ('delete', old.rowid, old.content); END;
      CREATE TABLE IF NOT EXISTS history_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS provider_preferences (source_key TEXT PRIMARY KEY, hidden INTEGER NOT NULL DEFAULT 0, mcp_ids TEXT);
    `);
    const columns = this.db.query<{ name: string }, []>("PRAGMA table_info(provider_messages)").all();
    if (!columns.some((column) => column.name === "parts_json")) {
      this.db.exec("ALTER TABLE provider_messages ADD COLUMN parts_json TEXT");
      this.db.exec("UPDATE provider_sessions SET indexed_version = NULL");
    }
    if (!columns.some((column) => column.name === "branch_json")) {
      this.db.exec("ALTER TABLE provider_messages ADD COLUMN branch_json TEXT");
      this.db.exec("UPDATE provider_sessions SET indexed_version = NULL");
    }
    this.branches = new NativeBranches(this.db);
  }

  get searchCacheEnabled() {
    return this.db.query<{ value: string }, []>("SELECT value FROM history_settings WHERE key = 'search_cache'").get()?.value !== "off";
  }
  get cacheStatus() {
    const counts = this.db.query<{ cachedMessages: number; cachedChats: number; bytes: number }, []>(
      "SELECT COUNT(*) AS cachedMessages, COUNT(DISTINCT conversation_id) AS cachedChats, COALESCE(SUM(length(CAST(content AS BLOB))), 0) AS bytes FROM provider_messages").get()!;
    return { enabled: this.searchCacheEnabled, ...counts };
  }
  setSearchCacheEnabled(enabled: boolean) {
    this.db.run("INSERT INTO history_settings(key, value) VALUES ('search_cache', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [enabled ? "on" : "off"]);
    if (!enabled) this.clearSearchCache();
  }
  clearSearchCache() {
    this.db.transaction(() => {
      this.db.run("DELETE FROM provider_messages");
      this.db.run("UPDATE provider_sessions SET indexed_version = NULL");
    })();
    this.db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
  }
  displayMessages(chat: ExternalChat, messages: ImportedMessage[]): Message[] {
    const id = nativeConversationID(chat.sourceKey);
    return messages.map((message, ordinal) => ({ id: `${id}:message:${ordinal}`, conversation_id: id,
      role: message.role, content: message.content, created_at: Math.round(message.createdAt),
      parts: message.parts, branchPoint: message.branchPoint }));
  }

  upsert(chat: ExternalChat) {
    const id = nativeConversationID(chat.sourceKey);
    this.db.run(`INSERT INTO provider_sessions (id, source_key, provider, json, updated_at) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at, unavailable = 0`,
    [id, chat.sourceKey, chat.provider, JSON.stringify(chat), Math.round(chat.updatedAt)]);
    return id;
  }
  hasSource(key: string) { return Boolean(this.db.query("SELECT 1 FROM provider_sessions WHERE source_key = ?").get(key)); }
  count() { return this.db.query<{ count: number }, []>("SELECT COUNT(*) AS count FROM provider_sessions").get()!.count; }
  source(id: string): ExternalChat | undefined {
    const row = this.db.query<SessionRow, [string]>("SELECT * FROM provider_sessions WHERE id = ?").get(id);
    return row ? JSON.parse(row.json) : undefined;
  }
  conversation(chat: ExternalChat, unavailable = false): Conversation {
    return { id: nativeConversationID(chat.sourceKey), title: chat.title, provider: chat.provider, origin: "provider",
      created_at: Math.round(chat.createdAt), updated_at: Math.round(chat.updatedAt), workspacePath: chat.workspacePath, model: chat.model,
      canResume: chat.canResume && !unavailable, historyWarning: unavailable ? "Provider history unavailable; showing an offline search cache." : chat.warning };
  }
  list(): Conversation[] {
    return this.db.query<SessionRow, []>(`SELECT s.* FROM provider_sessions s LEFT JOIN provider_preferences p ON p.source_key = s.source_key
      WHERE COALESCE(p.hidden, 0) = 0 ORDER BY s.updated_at DESC, s.id`).all()
      .map((row) => this.conversation(JSON.parse(row.json), Boolean(row.unavailable)));
  }
  get(id: string) {
    const row = this.db.query<SessionRow, [string]>("SELECT * FROM provider_sessions WHERE id = ?").get(id);
    if (!row) return undefined;
    return { conversation: this.conversation(JSON.parse(row.json), Boolean(row.unavailable)), messages: this.messages(id) };
  }
  messages(id: string): Message[] {
    return this.db.query<Message & { parts_json?: string; branch_json?: string }, [string]>(
      "SELECT id, conversation_id, role, content, created_at, parts_json, branch_json FROM provider_messages WHERE conversation_id = ? ORDER BY ordinal").all(id)
      .map(({ parts_json, branch_json, ...message }) => {
        try { return { ...message, parts: parts_json ? JSON.parse(parts_json) : undefined,
          branchPoint: branch_json ? JSON.parse(branch_json) : undefined }; }
        catch { return message; }
      });
  }
  cache(chat: ExternalChat, messages: ImportedMessage[]) {
    if (!this.searchCacheEnabled) return { conversation: this.conversation(chat), messages: this.displayMessages(chat, messages) };
    const id = nativeConversationID(chat.sourceKey);
    this.db.transaction(() => {
      this.upsert(chat);
      this.db.run("DELETE FROM provider_messages WHERE conversation_id = ?", [id]);
      const insert = this.db.prepare("INSERT INTO provider_messages (id, conversation_id, role, content, created_at, ordinal, parts_json, branch_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
      messages.forEach((message, ordinal) => insert.run(`${id}:message:${ordinal}`, id, message.role, message.content,
        Math.round(message.createdAt), ordinal, message.parts ? JSON.stringify(message.parts) : null,
        message.branchPoint ? JSON.stringify(message.branchPoint) : null));
      this.db.run("UPDATE provider_sessions SET indexed_version = ?, unavailable = 0 WHERE id = ?", [Math.round(chat.updatedAt), id]);
    })();
    return this.get(id)!;
  }
  needsMessages(chat: ExternalChat) {
    const row = this.db.query<{ indexed_version: number | null }, [string]>("SELECT indexed_version FROM provider_sessions WHERE source_key = ?").get(chat.sourceKey);
    return row?.indexed_version !== Math.round(chat.updatedAt);
  }
  branchState(id: string): ConversationBranchState {
    const available = this.get(id)?.conversation.canResume === true;
    const messages = this.messages(id);
    return { type: "conversation_branch_state", conversationId: id, branches: this.branches.family(id),
      messages: messages.flatMap((message, target) => message.role !== "user" ? [] : [{
        messageId: message.id, promptHash: promptFingerprint(message.content), canBranch: available && Boolean(message.branchPoint),
        canBranchAfter: available && Boolean(responseBranchPoint(messages, target)),
      }]) };
  }
  markUnavailable(provider: AgentKind) { this.db.run("UPDATE provider_sessions SET unavailable = 1 WHERE provider = ?", [provider]); }
  reconcile(provider: AgentKind, present: Set<string>) {
    this.db.transaction(() => {
      for (const row of this.db.query<{ id: string; source_key: string }, [string]>("SELECT id, source_key FROM provider_sessions WHERE provider = ?").all(provider)) {
        if (!present.has(row.source_key)) this.db.run("DELETE FROM provider_sessions WHERE id = ?", [row.id]);
      }
    })();
  }
  hide(id: string) {
    const source = this.source(id); if (!source) return;
    this.hideKey(source.sourceKey);
  }
  hideKey(key: string) { this.db.run("INSERT INTO provider_preferences (source_key, hidden) VALUES (?, 1) ON CONFLICT(source_key) DO UPDATE SET hidden = 1", [key]); }
  isHidden(key: string) { return Boolean(this.db.query<{ hidden: number }, [string]>("SELECT hidden FROM provider_preferences WHERE source_key = ?").get(key)?.hidden); }
  restoreHidden() { this.db.run("UPDATE provider_preferences SET hidden = 0"); }
  mcpIDs(id: string): string[] {
    const source = this.source(id); if (!source) return [];
    const row = this.db.query<{ mcp_ids: string | null }, [string]>("SELECT mcp_ids FROM provider_preferences WHERE source_key = ?").get(source.sourceKey);
    try { return row?.mcp_ids ? JSON.parse(row.mcp_ids) : []; } catch { return []; }
  }
  rememberMCPs(id: string, ids: string[]) {
    const source = this.source(id); if (!source) return;
    this.db.run(`INSERT INTO provider_preferences (source_key, mcp_ids) VALUES (?, ?)
      ON CONFLICT(source_key) DO UPDATE SET mcp_ids = excluded.mcp_ids`, [source.sourceKey, JSON.stringify([...new Set([...this.mcpIDs(id), ...ids])])]);
  }
  search(query: string, limit = 100): SearchResult[] {
    const words = matchQuery(query);
    if (!words) return [];
    try {
      return this.db.query<SearchResult, [string, number]>(`SELECT m.id AS message_id, m.conversation_id, m.role, m.content,
        snippet(provider_messages_fts, 0, '', '', '…', 24) AS snippet, m.created_at
        FROM provider_messages_fts f JOIN provider_messages m ON f.rowid = m.rowid
        JOIN provider_sessions s ON s.id = m.conversation_id LEFT JOIN provider_preferences p ON p.source_key = s.source_key
        WHERE provider_messages_fts MATCH ? AND COALESCE(p.hidden, 0) = 0 ORDER BY rank LIMIT ?`).all(words, limit);
    } catch { return []; }
  }
  searchChats(query: string, limit = 100): { conversation_id: string; snippet: string }[] {
    const words = matchQuery(query);
    if (!words) return [];
    return this.db.query<{ conversation_id: string; snippet: string }, [string, number]>(`
      WITH hits AS MATERIALIZED (
        SELECT m.conversation_id, snippet(provider_messages_fts, 0, '', '', '…', 24) AS snippet, rank AS score
        FROM provider_messages_fts f JOIN provider_messages m ON f.rowid = m.rowid
        JOIN provider_sessions s ON s.id = m.conversation_id LEFT JOIN provider_preferences p ON p.source_key = s.source_key
        WHERE provider_messages_fts MATCH ? AND COALESCE(p.hidden, 0) = 0)
      SELECT conversation_id, snippet FROM hits GROUP BY conversation_id ORDER BY MIN(score) LIMIT ?`).all(words, limit);
  }
  close() { this.db.close(); }
}
