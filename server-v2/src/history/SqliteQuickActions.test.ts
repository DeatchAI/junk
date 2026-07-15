import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { Database } from "bun:sqlite";

import { SqliteQuickActions } from "./SqliteQuickActions";

describe("SqliteQuickActions action definitions", () => {
  test("adds quick actions and workflows as separate action definitions", () => {
    const { dbPath, cleanup } = tempDb();
    try {
      const store = new SqliteQuickActions(dbPath);
      const quickAction = store.add({
        name: "Summarize",
        prompt: "Summarize this",
        mcpServerIds: ["detach-browser-tools"],
      });
      const workflow = store.add({
        name: "Unread Gmail",
        prompt: "List unread Gmail messages",
        kind: "workflow",
        mcpServerIds: ["composio-mcp"],
      });

      expect(quickAction.kind).toBe("quick_action");
      expect(quickAction.trigger).toBe("selection_menu");
      expect(quickAction.inputPolicy).toBe("optional_selection");
      expect(quickAction.mcpServerIds).toEqual(["detach-browser-tools"]);
      expect(workflow.kind).toBe("workflow");
      expect(workflow.trigger).toBe("manual");
      expect(workflow.inputPolicy).toBe("none");
      expect(store.list("quick_action").map((action) => action.id)).toEqual([quickAction.id]);
      expect(store.list("workflow").map((action) => action.id)).toEqual([workflow.id]);
    } finally {
      cleanup();
    }
  });

  test("partial updates do not erase selected MCP servers or position", () => {
    const { dbPath, cleanup } = tempDb();
    try {
      const store = new SqliteQuickActions(dbPath);
      const action = store.add({
        name: "Gmail",
        prompt: "List unread email",
        mcpServerIds: ["composio-mcp"],
        position: 7,
      });

      const updated = store.update(action.id, { name: "Gmail unread" });

      expect(updated?.mcpServerIds).toEqual(["composio-mcp"]);
      expect(updated?.position).toBe(7);
      expect(updated?.prompt).toBe("List unread email");
    } finally {
      cleanup();
    }
  });

  test("persists learned action skill metadata", () => {
    const { dbPath, cleanup } = tempDb();
    try {
      const store = new SqliteQuickActions(dbPath);
      const action = store.add({
        name: "Notes todo",
        prompt: "Save selected text as a todo in Notes",
      });

      const updated = store.update(action.id, {
        learnedSkillPath: "/tmp/detach-action-skill/SKILL.md",
        learnedSkillVersion: 1,
        learningStatus: "ready",
        lastSuccessfulRunAt: 123,
      });

      expect(updated).toMatchObject({
        learnedSkillPath: "/tmp/detach-action-skill/SKILL.md",
        learnedSkillVersion: 1,
        learningStatus: "ready",
        lastSuccessfulRunAt: 123,
      });
      expect(store.get(action.id)).toMatchObject({
        learnedSkillPath: "/tmp/detach-action-skill/SKILL.md",
        learnedSkillVersion: 1,
        learningStatus: "ready",
        lastSuccessfulRunAt: 123,
      });
    } finally {
      cleanup();
    }
  });

  test("migrates old quick action rows with action definition defaults", () => {
    const { dbPath, cleanup } = tempDb();
    try {
      const db = new Database(dbPath, { create: true });
      db.run(
        `CREATE TABLE quick_actions (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          prompt TEXT NOT NULL,
          integrations TEXT,
          system_image TEXT,
          shortcut TEXT,
          position INTEGER DEFAULT 0,
          enabled INTEGER DEFAULT 1,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )`
      );
      db.run(
        `INSERT INTO quick_actions (id, name, prompt, integrations, system_image, shortcut, position, enabled, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        ["legacy", "Legacy", "Do old thing", null, null, null, 3, 1, 1, 1]
      );
      db.close();

      const store = new SqliteQuickActions(dbPath);
      expect(store.list("quick_action")).toMatchObject([
        {
          id: "legacy",
          kind: "quick_action",
          trigger: "selection_menu",
          inputPolicy: "optional_selection",
          executionMode: "run_immediately",
          position: 3,
        },
      ]);
    } finally {
      cleanup();
    }
  });
});

function tempDb() {
  const dir = mkdtempSync(join(tmpdir(), "detach-actions-"));
  return {
    dbPath: join(dir, "actions.sqlite"),
    cleanup: () => rmSync(dir, { recursive: true, force: true }),
  };
}
