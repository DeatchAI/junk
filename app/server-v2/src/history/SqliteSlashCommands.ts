import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type { ComposerMode, SlashCommandDefinition } from "../protocol/messages";
import { defaultDatabasePath } from "./databasePath";

const schema = `
CREATE TABLE IF NOT EXISTS slash_commands (
  id TEXT PRIMARY KEY,
  command TEXT NOT NULL UNIQUE COLLATE NOCASE,
  title TEXT NOT NULL,
  subtitle TEXT,
  system_image TEXT,
  replacement_text TEXT,
  prompt_instruction TEXT,
  mode TEXT,
  enabled INTEGER DEFAULT 1,
  position INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
`;

interface SlashCommandRow {
  id: string;
  command: string;
  title: string;
  subtitle: string | null;
  system_image: string | null;
  replacement_text: string | null;
  prompt_instruction: string | null;
  mode: string | null;
  enabled: number;
  position: number;
  created_at: number;
  updated_at: number;
}

interface SlashCommandInput {
  command: string;
  title: string;
  subtitle?: string;
  systemImage?: string;
  replacementText?: string;
  promptInstruction?: string;
  mode?: ComposerMode;
  enabled?: boolean;
  position?: number;
}

const selectColumns = `
  SELECT
    id,
    command,
    title,
    subtitle,
    system_image,
    replacement_text,
    prompt_instruction,
    mode,
    enabled,
    position,
    created_at,
    updated_at
`;

export class SqliteSlashCommands {
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

  list() {
    return this.db
      .query<SlashCommandRow, []>(`${selectColumns} FROM slash_commands WHERE enabled = 1 ORDER BY position ASC, title ASC`)
      .all()
      .map(rowToSlashCommand);
  }

  get(id: string) {
    const row = this.db
      .query<SlashCommandRow, [string]>(`${selectColumns} FROM slash_commands WHERE id = ?`)
      .get(id);
    return row ? rowToSlashCommand(row) : undefined;
  }

  getByCommand(command: string) {
    const row = this.db
      .query<SlashCommandRow, [string]>(`${selectColumns} FROM slash_commands WHERE command = ? COLLATE NOCASE`)
      .get(normalizeCommand(command));
    return row ? rowToSlashCommand(row) : undefined;
  }

  add(input: SlashCommandInput) {
    const now = Date.now();
    const id = generateId("slash");
    const command = normalizeCommand(input.command);
    const maxPosition =
      this.db.query<{ maxPosition: number | null }, []>("SELECT MAX(position) as maxPosition FROM slash_commands")
        .get()?.maxPosition ?? -1;
    const position = input.position ?? maxPosition + 1;
    const enabled = input.enabled ?? true;

    this.db
      .query(
        `INSERT INTO slash_commands (
          id, command, title, subtitle, system_image, replacement_text, prompt_instruction, mode,
          enabled, position, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
      )
      .run(
        id,
        command,
        input.title.trim(),
        input.subtitle?.trim() ?? null,
        input.systemImage ?? null,
        input.replacementText?.trim() ?? null,
        input.promptInstruction?.trim() ?? null,
        input.mode ?? null,
        enabled ? 1 : 0,
        position,
        now,
        now
      );

    return this.get(id)!;
  }

  update(id: string, input: Partial<SlashCommandInput>) {
    const existing = this.get(id);
    if (!existing) return undefined;

    const now = Date.now();
    const command = input.command ? normalizeCommand(input.command) : existing.command;
    const title = input.title?.trim() ?? existing.title;
    const subtitle = input.subtitle !== undefined ? input.subtitle?.trim() ?? null : existing.subtitle ?? null;
    const systemImage = input.systemImage !== undefined ? input.systemImage ?? null : existing.systemImage ?? null;
    const replacementText =
      input.replacementText !== undefined ? input.replacementText?.trim() ?? null : existing.replacementText ?? null;
    const promptInstruction =
      input.promptInstruction !== undefined
        ? input.promptInstruction?.trim() ?? null
        : existing.promptInstruction ?? null;
    const mode = input.mode !== undefined ? input.mode ?? null : existing.mode ?? null;
    const enabled = input.enabled ?? existing.enabled;
    const position = input.position ?? existing.position;

    this.db
      .query(
        `UPDATE slash_commands SET
          command = ?,
          title = ?,
          subtitle = ?,
          system_image = ?,
          replacement_text = ?,
          prompt_instruction = ?,
          mode = ?,
          enabled = ?,
          position = ?,
          updated_at = ?
        WHERE id = ?`
      )
      .run(
        command,
        title,
        subtitle,
        systemImage,
        replacementText,
        promptInstruction,
        mode,
        enabled ? 1 : 0,
        position,
        now,
        id
      );

    return this.get(id);
  }

  delete(id: string) {
    const result = this.db.query("DELETE FROM slash_commands WHERE id = ?").run(id);
    return result.changes > 0;
  }
}

function rowToSlashCommand(row: SlashCommandRow): SlashCommandDefinition {
  return {
    id: row.id,
    command: row.command,
    title: row.title,
    subtitle: row.subtitle ?? undefined,
    systemImage: row.system_image ?? undefined,
    replacementText: row.replacement_text ?? undefined,
    promptInstruction: row.prompt_instruction ?? undefined,
    mode: (row.mode as ComposerMode | null) ?? undefined,
    enabled: row.enabled === 1,
    position: row.position,
    isCustom: true,
  };
}

function normalizeCommand(command: string) {
  return command.trim().toLowerCase();
}

function generateId(prefix: string) {
  return `${prefix}_${crypto.randomUUID().replace(/-/g, "").slice(0, 12)}`;
}
