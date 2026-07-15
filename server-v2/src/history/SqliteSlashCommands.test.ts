import { describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { SqliteSlashCommands } from "./SqliteSlashCommands";

describe("SqliteSlashCommands", () => {
  test("adds and lists custom slash commands", () => {
    const { dbPath, cleanup } = tempDb();
    try {
      const store = new SqliteSlashCommands(dbPath);
      const command = store.add({
        command: "bullet-reply",
        title: "Bullet Reply",
        subtitle: "Always answer in bullets",
        promptInstruction: "Respond in concise bullet points.",
      });

      expect(command.command).toBe("bullet-reply");
      expect(command.promptInstruction).toBe("Respond in concise bullet points.");
      expect(store.list().map((item) => item.id)).toEqual([command.id]);
    } finally {
      cleanup();
    }
  });

  test("rejects duplicate command names case-insensitively", () => {
    const { dbPath, cleanup } = tempDb();
    try {
      const store = new SqliteSlashCommands(dbPath);
      store.add({
        command: "triage",
        title: "Triage",
        promptInstruction: "Triage the issue first.",
      });

      expect(() =>
        store.add({
          command: "TRIAGE",
          title: "Duplicate",
          promptInstruction: "Should fail",
        })
      ).toThrow();
    } finally {
      cleanup();
    }
  });
});

function tempDb() {
  const dir = mkdtempSync(join(tmpdir(), "detach-slash-commands-"));
  const dbPath = join(dir, "chats.sqlite");
  return {
    dbPath,
    cleanup() {
      rmSync(dir, { recursive: true, force: true });
    },
  };
}
