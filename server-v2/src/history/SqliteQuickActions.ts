import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import type {
  ActionDefinition,
  ActionExecutionMode,
  ActionInputPolicy,
  ActionKind,
  ActionTrigger,
  QuickAction,
  SkillAttachment,
} from "../protocol/messages";
import { defaultDatabasePath } from "./databasePath";

const schema = `
CREATE TABLE IF NOT EXISTS quick_actions (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  prompt TEXT NOT NULL,
  integrations TEXT,
  system_image TEXT,
  shortcut TEXT,
  position INTEGER DEFAULT 0,
  enabled INTEGER DEFAULT 1,
  kind TEXT DEFAULT 'quick_action',
  trigger TEXT DEFAULT 'selection_menu',
  input_policy TEXT DEFAULT 'optional_selection',
  execution_mode TEXT DEFAULT 'run_immediately',
  mcp_server_ids TEXT,
  skills TEXT,
  learned_skill_path TEXT,
  learned_skill_version INTEGER DEFAULT 0,
  learning_status TEXT DEFAULT 'none',
  last_successful_run_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
`;

interface QuickActionRow {
  id: string;
  name: string;
  prompt: string;
  integrations: string | null;
  system_image: string | null;
  shortcut: string | null;
  position: number;
  enabled: number;
  kind?: string | null;
  trigger?: string | null;
  input_policy?: string | null;
  execution_mode?: string | null;
  mcp_server_ids?: string | null;
  skills?: string | null;
  learned_skill_path?: string | null;
  learned_skill_version?: number | null;
  learning_status?: string | null;
  last_successful_run_at?: number | null;
  created_at: number;
  updated_at: number;
}

interface ActionDefinitionInput {
  name: string;
  prompt: string;
  kind?: ActionKind;
  trigger?: ActionTrigger;
  inputPolicy?: ActionInputPolicy;
  executionMode?: ActionExecutionMode;
  integrations?: string[];
  mcpServerIds?: string[];
  skills?: SkillAttachment[];
  learnedSkillPath?: string;
  learnedSkillVersion?: number;
  learningStatus?: ActionDefinition["learningStatus"];
  lastSuccessfulRunAt?: number;
  systemImage?: string;
  shortcut?: string;
  position?: number;
  enabled?: boolean;
}

export class SqliteQuickActions {
  private readonly db: Database;

  constructor(dbPath = defaultDatabasePath()) {
    mkdirSync(dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath, { create: true });
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec("PRAGMA synchronous = NORMAL;");
    this.db.exec("PRAGMA busy_timeout = 5000;");
    this.db.exec(schema);
    this.migrateActionDefinitionColumns();
  }

  list(kind: ActionKind = "quick_action") {
    return this.db
      .query<QuickActionRow, [ActionKind]>(
        `${selectColumns} FROM quick_actions WHERE COALESCE(kind, 'quick_action') = ? AND enabled = 1 ORDER BY position ASC`
      )
      .all(kind)
      .map(rowToQuickAction);
  }

  add(input: ActionDefinitionInput) {
    const now = Date.now();
    const id = generateId("action");
    const kind = input.kind ?? "quick_action";
    const trigger = input.trigger ?? defaultTrigger(kind);
    const inputPolicy = input.inputPolicy ?? defaultInputPolicy(kind);
    const executionMode = input.executionMode ?? defaultExecutionMode();
    const maxPosition =
      this.db.query<{ maxPosition: number | null }, [ActionKind]>(
        "SELECT MAX(position) as maxPosition FROM quick_actions WHERE COALESCE(kind, 'quick_action') = ?"
      ).get(kind)
        ?.maxPosition ?? -1;
    const position = input.position ?? maxPosition + 1;
    const enabled = input.enabled ?? true;

    this.db.run(
      `INSERT INTO quick_actions (id, name, prompt, integrations, system_image, shortcut, position, enabled, kind, trigger, input_policy, execution_mode, mcp_server_ids, skills, learned_skill_path, learned_skill_version, learning_status, last_successful_run_at, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        id,
        input.name,
        input.prompt,
        serializeStringArray(input.integrations),
        input.systemImage ?? null,
        input.shortcut ?? null,
        position,
        enabled ? 1 : 0,
        kind,
        trigger,
        inputPolicy,
        executionMode,
        serializeStringArray(input.mcpServerIds),
        serializeSkills(input.skills),
        input.learnedSkillPath ?? null,
        input.learnedSkillVersion ?? 0,
        input.learningStatus ?? "none",
        input.lastSuccessfulRunAt ?? null,
        now,
        now,
      ]
    );

    return {
      id,
      name: input.name,
      prompt: input.prompt,
      kind,
      trigger,
      inputPolicy,
      executionMode,
      integrations: input.integrations,
      mcpServerIds: input.mcpServerIds,
      skills: input.skills,
      learnedSkillPath: input.learnedSkillPath,
      learnedSkillVersion: input.learnedSkillVersion ?? 0,
      learningStatus: input.learningStatus ?? "none",
      lastSuccessfulRunAt: input.lastSuccessfulRunAt,
      systemImage: input.systemImage,
      shortcut: input.shortcut,
      enabled,
      position,
      created_at: now,
      updated_at: now,
    } satisfies QuickAction;
  }

  update(id: string, input: Partial<Omit<ActionDefinition, "id" | "created_at" | "updated_at">>) {
    const current = this.get(id);
    if (!current) return undefined;

    const next: ActionDefinition = {
      ...current,
      ...withoutUndefined(input),
      updated_at: Date.now(),
    };

    this.db.run(
      `UPDATE quick_actions
       SET name = ?, prompt = ?, integrations = ?, system_image = ?, shortcut = ?, position = ?, enabled = ?, kind = ?, trigger = ?, input_policy = ?, execution_mode = ?, mcp_server_ids = ?, skills = ?, learned_skill_path = ?, learned_skill_version = ?, learning_status = ?, last_successful_run_at = ?, updated_at = ?
       WHERE id = ?`,
      [
        next.name,
        next.prompt,
        serializeStringArray(next.integrations),
        next.systemImage ?? null,
        next.shortcut ?? null,
        next.position,
        next.enabled ? 1 : 0,
        next.kind,
        next.trigger,
        next.inputPolicy,
        next.executionMode,
        serializeStringArray(next.mcpServerIds),
        serializeSkills(next.skills),
        next.learnedSkillPath ?? null,
        next.learnedSkillVersion ?? 0,
        next.learningStatus ?? "none",
        next.lastSuccessfulRunAt ?? null,
        next.updated_at,
        id,
      ]
    );

    return next;
  }

  delete(id: string) {
    const result = this.db.run("DELETE FROM quick_actions WHERE id = ?", [id]);
    return result.changes > 0;
  }

  get(id: string) {
    const row = this.db
      .query<QuickActionRow, [string]>(
        `${selectColumns} FROM quick_actions WHERE id = ?`
      )
      .get(id);

    return row ? rowToQuickAction(row) : undefined;
  }

  private migrateActionDefinitionColumns() {
    const columns = new Set(
      this.db
        .query<{ name: string }, []>("PRAGMA table_info(quick_actions)")
        .all()
        .map((column) => column.name)
    );

    const additions: Array<[string, string]> = [
      ["kind", "TEXT DEFAULT 'quick_action'"],
      ["trigger", "TEXT DEFAULT 'selection_menu'"],
      ["input_policy", "TEXT DEFAULT 'optional_selection'"],
      ["execution_mode", "TEXT DEFAULT 'run_immediately'"],
      ["mcp_server_ids", "TEXT"],
      ["skills", "TEXT"],
      ["learned_skill_path", "TEXT"],
      ["learned_skill_version", "INTEGER DEFAULT 0"],
      ["learning_status", "TEXT DEFAULT 'none'"],
      ["last_successful_run_at", "INTEGER"],
    ];

    for (const [name, definition] of additions) {
      if (!columns.has(name)) {
        this.db.exec(`ALTER TABLE quick_actions ADD COLUMN ${name} ${definition};`);
      }
    }
  }
}

function rowToQuickAction(row: QuickActionRow): QuickAction {
  const kind = parseKind(row.kind);
  return {
    id: row.id,
    name: row.name,
    prompt: row.prompt,
    kind,
    trigger: parseTrigger(row.trigger, kind),
    inputPolicy: parseInputPolicy(row.input_policy, kind),
    executionMode: parseExecutionMode(row.execution_mode),
    integrations: parseIntegrations(row.integrations),
    mcpServerIds: parseStringArray(row.mcp_server_ids),
    skills: parseSkills(row.skills),
    learnedSkillPath: row.learned_skill_path ?? undefined,
    learnedSkillVersion: row.learned_skill_version ?? undefined,
    learningStatus: parseLearningStatus(row.learning_status),
    lastSuccessfulRunAt: row.last_successful_run_at ?? undefined,
    systemImage: row.system_image ?? undefined,
    shortcut: row.shortcut ?? undefined,
    position: row.position,
    enabled: row.enabled === 1,
    created_at: row.created_at,
    updated_at: row.updated_at,
  };
}

const selectColumns =
  "SELECT id, name, prompt, integrations, system_image, shortcut, position, enabled, kind, trigger, input_policy, execution_mode, mcp_server_ids, skills, learned_skill_path, learned_skill_version, learning_status, last_successful_run_at, created_at, updated_at";

function parseIntegrations(value: string | null) {
  return parseStringArray(value);
}

function parseStringArray(value: string | null | undefined) {
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.filter((item): item is string => typeof item === "string") : undefined;
  } catch {
    return undefined;
  }
}

function parseSkills(value: string | null | undefined) {
  if (!value) return undefined;
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed)
      ? parsed.filter(
          (item): item is SkillAttachment =>
            typeof item?.id === "string" && typeof item?.name === "string" && typeof item?.path === "string"
        )
      : undefined;
  } catch {
    return undefined;
  }
}

function serializeStringArray(value?: string[]) {
  return value?.length ? JSON.stringify(value) : null;
}

function serializeSkills(value?: SkillAttachment[]) {
  return value?.length ? JSON.stringify(value) : null;
}

function withoutUndefined<T extends Record<string, unknown>>(value: T) {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined)) as Partial<T>;
}

function parseKind(value: string | null | undefined): ActionKind {
  return value === "workflow" ? "workflow" : "quick_action";
}

function parseTrigger(value: string | null | undefined, kind: ActionKind): ActionTrigger {
  if (value === "manual" || value === "hotkey" || value === "selection_menu") return value;
  return defaultTrigger(kind);
}

function parseInputPolicy(value: string | null | undefined, kind: ActionKind): ActionInputPolicy {
  if (value === "requires_selection" || value === "optional_selection" || value === "none") return value;
  return defaultInputPolicy(kind);
}

function parseExecutionMode(value: string | null | undefined): ActionExecutionMode {
  if (value === "open_composer" || value === "run_immediately") return value;
  return defaultExecutionMode();
}

function parseLearningStatus(value: string | null | undefined): ActionDefinition["learningStatus"] {
  if (value === "learning" || value === "ready" || value === "stale" || value === "failed") return value;
  return "none";
}

function defaultTrigger(kind: ActionKind): ActionTrigger {
  return kind === "workflow" ? "manual" : "selection_menu";
}

function defaultInputPolicy(kind: ActionKind): ActionInputPolicy {
  return kind === "workflow" ? "none" : "optional_selection";
}

function defaultExecutionMode(): ActionExecutionMode {
  return "run_immediately";
}

function generateId(prefix: string) {
  return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
}
