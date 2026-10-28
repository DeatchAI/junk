import type { Database } from "bun:sqlite";
import type { ConversationBranch } from "./BranchTypes";

/** Relationships only; transcripts and execution stay in provider-owned sessions. */
export class NativeBranches {
  constructor(private readonly db: Database) {
    db.exec(`CREATE TABLE IF NOT EXISTS conversation_branches (
      id TEXT PRIMARY KEY, root_id TEXT NOT NULL, parent_id TEXT NOT NULL,
      message_id TEXT NOT NULL, message_number INTEGER NOT NULL, created_at INTEGER NOT NULL)`);
  }

  add(id: string, parentId: string, messageId: string, messageNumber: number) {
    if (id === parentId) throw new Error("The provider did not create an independent conversation.");
    const parent = this.db.query<{ root_id: string }, [string]>("SELECT root_id FROM conversation_branches WHERE id = ?").get(parentId);
    this.db.run(`INSERT OR IGNORE INTO conversation_branches VALUES (?, ?, ?, ?, ?, ?)`,
      [id, parent?.root_id ?? parentId, parentId, messageId, messageNumber, Date.now()]);
  }

  family(id: string): ConversationBranch[] {
    const record = this.db.query<{ root_id: string }, [string]>("SELECT root_id FROM conversation_branches WHERE id = ?").get(id);
    const root = record?.root_id ?? id;
    const rows = this.db.query<{ id: string; parent_id?: string; message_number?: number; json: string }, [string, string]>(`
      SELECT s.id, b.parent_id, b.message_number, s.json FROM provider_sessions s
      LEFT JOIN conversation_branches b ON b.id = s.id
      LEFT JOIN provider_preferences p ON p.source_key = s.source_key
      WHERE (s.id = ? OR b.root_id = ?) AND COALESCE(p.hidden, 0) = 0
      ORDER BY CASE WHEN s.id = b.root_id OR b.id IS NULL THEN 0 ELSE 1 END, b.created_at, s.id`).all(root, root);
    return rows.map((row) => ({ id: row.id, parentId: row.parent_id ?? undefined,
      messageNumber: row.message_number ?? undefined, title: JSON.parse(row.json).title || "Conversation" }));
  }
}
