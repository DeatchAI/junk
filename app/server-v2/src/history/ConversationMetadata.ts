import type { Database } from "bun:sqlite";
import type { AgentKind, Conversation } from "../protocol/messages";
import type { ExternalChat, ImportedMessage, NativeSession } from "../imports/ImportTypes";

/** Provider labels, import provenance and native bindings are separate from display messages. */
export class ConversationMetadata {
  constructor(private readonly db: Database) {
    db.exec(`
      CREATE TABLE IF NOT EXISTS conversation_metadata (
        conversation_id TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
        provider TEXT, workspace_path TEXT, model TEXT
      );
      CREATE TABLE IF NOT EXISTS conversation_imports (
        conversation_id TEXT PRIMARY KEY REFERENCES conversations(id) ON DELETE CASCADE,
        source_key TEXT NOT NULL UNIQUE, provider TEXT NOT NULL, can_resume INTEGER NOT NULL, warning TEXT
      );
      CREATE TABLE IF NOT EXISTS conversation_sessions (
        conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
        provider TEXT NOT NULL, session_id TEXT NOT NULL, workspace_path TEXT NOT NULL,
        PRIMARY KEY (conversation_id, provider)
      );
    `);
  }

  decorate(conversation: Conversation): Conversation {
    const row = this.db.query<any, [string]>("SELECT * FROM conversation_metadata WHERE conversation_id = ?").get(conversation.id);
    const source = this.db.query<any, [string]>("SELECT provider, can_resume, warning FROM conversation_imports WHERE conversation_id = ?").get(conversation.id);
    return { ...conversation,
      ...(row?.provider ? { provider: row.provider } : {}),
      ...(row?.workspace_path ? { workspacePath: row.workspace_path } : {}),
      ...(row?.model ? { model: row.model } : {}),
      ...(source ? { importSource: { provider: source.provider, canResume: Boolean(source.can_resume) && source.provider === row?.provider,
        ...(source.warning ? { warning: source.warning } : {}) } } : {}),
    };
  }

  record(id: string, provider: AgentKind, workspacePath?: string, model?: string) {
    this.db.run(`INSERT INTO conversation_metadata (conversation_id, provider, workspace_path, model) VALUES (?, ?, ?, ?)
      ON CONFLICT(conversation_id) DO UPDATE SET provider = excluded.provider,
      workspace_path = COALESCE(excluded.workspace_path, conversation_metadata.workspace_path), model = excluded.model`,
    [id, provider, workspacePath ?? null, model ?? null]);
  }

  session(id: string, provider: AgentKind): NativeSession | undefined {
    return this.db.query<NativeSession, [string, string]>(
      "SELECT session_id AS id, workspace_path AS workspacePath FROM conversation_sessions WHERE conversation_id = ? AND provider = ?"
    ).get(id, provider) ?? undefined;
  }

  bind(id: string, provider: AgentKind, session: NativeSession) {
    this.db.run(`INSERT INTO conversation_sessions VALUES (?, ?, ?, ?)
      ON CONFLICT(conversation_id, provider) DO UPDATE SET session_id = excluded.session_id, workspace_path = excluded.workspace_path`,
    [id, provider, session.id, session.workspacePath]);
  }

  invalidateSessions(id: string) {
    this.db.run("DELETE FROM conversation_sessions WHERE conversation_id = ?", [id]);
    this.db.run("UPDATE conversation_imports SET can_resume = 0, warning = ? WHERE conversation_id = ?",
      ["Edited history continues as a new conversation.", id]);
  }

  hasSource(key: string) {
    return Boolean(this.db.query("SELECT 1 FROM conversation_imports WHERE source_key = ?").get(key));
  }

  importedSource(id: string) {
    return this.db.query<{ sourceKey: string; provider: AgentKind; sessionID: string | null }, [string]>(`
      SELECT i.source_key AS sourceKey, i.provider, s.session_id AS sessionID FROM conversation_imports i
      LEFT JOIN conversation_sessions s ON s.conversation_id = i.conversation_id AND s.provider = i.provider
      WHERE i.conversation_id = ?`).get(id);
  }

  import(chat: ExternalChat, messages: ImportedMessage[]) {
    return this.db.transaction(() => {
      if (this.hasSource(chat.sourceKey)) return undefined;
      if (!messages.length) throw new Error("This session has no readable conversation messages.");
      const id = `conv_${crypto.randomUUID()}`;
      this.db.run("INSERT INTO conversations (id, title, created_at, updated_at, title_attempted) VALUES (?, ?, ?, ?, 1)",
        [id, chat.title, chat.createdAt, chat.updatedAt]);
      this.record(id, chat.provider, chat.workspacePath, chat.model);
      this.db.run("INSERT INTO conversation_imports VALUES (?, ?, ?, ?, ?)",
        [id, chat.sourceKey, chat.provider, Number(chat.canResume), chat.warning ?? null]);
      const insert = this.db.prepare("INSERT INTO messages (id, conversation_id, role, content, created_at, parts_json) VALUES (?, ?, ?, ?, ?, ?)");
      for (const message of messages) insert.run(`msg_${crypto.randomUUID()}`, id, message.role, message.content, message.createdAt, message.parts ? JSON.stringify(message.parts) : null);
      if (chat.canResume && chat.workspacePath) this.bind(id, chat.provider, { id: chat.sourceId, workspacePath: chat.workspacePath });
      return id;
    })();
  }
}
