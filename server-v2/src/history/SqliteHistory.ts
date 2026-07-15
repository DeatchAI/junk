import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { Conversation, Message, SearchResult } from "../protocol/messages";
import { defaultDatabasePath } from "./databasePath";

const schema = `
CREATE TABLE IF NOT EXISTS conversations (
  id TEXT PRIMARY KEY,
  title TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY,
  conversation_id TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS attachments (
  id TEXT PRIMARY KEY,
  message_id TEXT NOT NULL,
  file_path TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS conversation_mcp_servers (
  conversation_id TEXT NOT NULL,
  server_id TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (conversation_id, server_id),
  FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_created ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_attachments_message ON attachments(message_id);
CREATE INDEX IF NOT EXISTS idx_conversation_mcp_servers_conversation ON conversation_mcp_servers(conversation_id);

CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
  content,
  content='messages',
  content_rowid='rowid'
);

CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
  INSERT INTO messages_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
END;

CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', OLD.rowid, OLD.content);
END;

CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
  INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', OLD.rowid, OLD.content);
  INSERT INTO messages_fts(rowid, content) VALUES (NEW.rowid, NEW.content);
END;
`;

export class SqliteHistory {
  private readonly db: Database;

  constructor(dbPath = defaultDatabasePath()) {
    mkdirSync(dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath, { create: true });
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec("PRAGMA synchronous = NORMAL;");
    this.db.exec("PRAGMA busy_timeout = 5000;");
    this.db.exec(schema);
    rebuildFtsIfEmpty(this.db);
  }

  list(limit = 50, offset = 0) {
    return this.db
      .query<Conversation, [number, number]>(
        "SELECT id, title, created_at, updated_at FROM conversations ORDER BY updated_at DESC LIMIT ? OFFSET ?"
      )
      .all(limit, offset);
  }

  get(conversationId: string) {
    const conversation = this.db
      .query<Conversation, [string]>("SELECT id, title, created_at, updated_at FROM conversations WHERE id = ?")
      .get(conversationId);

    if (!conversation) return undefined;

    return {
      conversation,
      messages: this.getMessages(conversationId),
    };
  }

  deleteConversation(conversationId: string) {
    this.db.run("DELETE FROM conversations WHERE id = ?", [conversationId]);
  }

  getMCPServerIds(conversationId: string): string[] {
    return this.db
      .query<{ server_id: string }, [string]>(
        "SELECT server_id FROM conversation_mcp_servers WHERE conversation_id = ? ORDER BY created_at ASC"
      )
      .all(conversationId)
      .map((row) => row.server_id);
  }

  mergeMCPServerIds(conversationId: string, serverIds: string[]) {
    const uniqueIds = [...new Set(serverIds.map((serverId) => serverId.trim()).filter(Boolean))];
    if (uniqueIds.length === 0) return;

    const now = Date.now();
    const insert = this.db.prepare(
      "INSERT OR IGNORE INTO conversation_mcp_servers (conversation_id, server_id, created_at) VALUES (?, ?, ?)"
    );
    const transaction = this.db.transaction((ids: string[]) => {
      for (const serverId of ids) insert.run(conversationId, serverId, now);
    });
    transaction(uniqueIds);
  }

  addUserMessage(conversationId: string | undefined, content: string) {
    const id = conversationId || generateId("conv");
    const message = this.addMessage(id, "user", content);
    const conversation = this.get(id)?.conversation;

    if (!conversation) {
      throw new Error(`Failed to create conversation ${id}`);
    }

    return { conversation, message };
  }

  addAssistantMessage(conversationId: string, content: string) {
    return this.addMessage(conversationId, "assistant", content);
  }

  editMessage(messageId: string, content: string) {
    const result = this.db.run("UPDATE messages SET content = ? WHERE id = ?", [content, messageId]);
    return result.changes > 0;
  }

  deleteMessage(messageId: string) {
    const result = this.db.run("DELETE FROM messages WHERE id = ?", [messageId]);
    return result.changes > 0;
  }

  search(query: string, limit = 20): SearchResult[] {
    const trimmed = query.trim();
    if (!trimmed) return [];

    try {
      return this.db
        .query<SearchResult, [string, number]>(
          `SELECT
             m.id as message_id,
             m.conversation_id,
             m.role,
             m.content,
             snippet(messages_fts, 0, '<mark>', '</mark>', '...', 32) as snippet,
             m.created_at
           FROM messages_fts fts
           JOIN messages m ON fts.rowid = m.rowid
           WHERE messages_fts MATCH ?
           ORDER BY rank
           LIMIT ?`
        )
        .all(escapeFtsQuery(trimmed), limit);
    } catch {
      return this.db
        .query<SearchResult, [string, number]>(
          `SELECT
             id as message_id,
             conversation_id,
             role,
             content,
             content as snippet,
             created_at
           FROM messages
           WHERE content LIKE ?
           ORDER BY created_at DESC
           LIMIT ?`
        )
        .all(`%${trimmed}%`, limit);
    }
  }

  private addMessage(conversationId: string, role: "user" | "assistant", content: string): Message {
    const now = Date.now();
    const id = generateId("msg");
    const existing = this.get(conversationId)?.conversation;

    if (!existing) {
      const title = role === "user" ? createTitle(content) : null;
      this.db.run("INSERT INTO conversations (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)", [
        conversationId,
        title,
        now,
        now,
      ]);
    } else {
      this.db.run("UPDATE conversations SET updated_at = ? WHERE id = ?", [now, conversationId]);
      if (!existing.title && role === "user") {
        this.db.run("UPDATE conversations SET title = ? WHERE id = ?", [createTitle(content), conversationId]);
      }
    }

    this.db.run("INSERT INTO messages (id, conversation_id, role, content, created_at) VALUES (?, ?, ?, ?, ?)", [
      id,
      conversationId,
      role,
      content,
      now,
    ]);

    return { id, conversation_id: conversationId, role, content, created_at: now };
  }

  private getMessages(conversationId: string) {
    return this.db
      .query<Message, [string]>(
        "SELECT id, conversation_id, role, content, created_at FROM messages WHERE conversation_id = ? ORDER BY created_at ASC"
      )
      .all(conversationId);
  }
}

function createTitle(content: string) {
  const cleaned = content.replace(/\s+/g, " ").trim();
  if (!cleaned) return "New chat";
  return cleaned.length > 100 ? `${cleaned.slice(0, 97)}...` : cleaned;
}

function generateId(prefix: string) {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}

function escapeFtsQuery(query: string) {
  return query
    .split(/\s+/)
    .filter(Boolean)
    .map((term) => `"${term.replaceAll('"', '""')}"`)
    .join(" ");
}

function rebuildFtsIfEmpty(db: Database) {
  const hasMessages = db.query<{ count: number }, []>("SELECT COUNT(*) as count FROM messages").get()?.count ?? 0;
  const hasFts = db.query<{ count: number }, []>("SELECT COUNT(*) as count FROM messages_fts").get()?.count ?? 0;

  if (hasMessages > 0 && hasFts === 0) {
    db.exec("INSERT INTO messages_fts(rowid, content) SELECT rowid, content FROM messages;");
  }
}
