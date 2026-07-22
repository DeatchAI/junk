import { describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import type { BrowserTraceEntry } from "./BrowserAutomation";
import { learnedBrowserSkillAttachments, learnBrowserSkillFromArtifacts } from "./BrowserSkillManager";

describe("learned browser skills", () => {
  test("learns stable locators only after explicit verified completion", () => {
    const root = mkdtempSync(join(tmpdir(), "detach-browser-skills-"));
    try {
      const trace: BrowserTraceEntry[] = [{
        id: "trace-1",
        runId: "run-1",
        command: "browser.execute_code",
        engine: "signed_in",
        startedAt: 1,
        durationMs: 10,
        ok: true,
        args: {
          code: `
            const username = page.getByLabel("Username or Email", { exact: true });
            const password = page.getByPlaceholder("Password", { exact: true });
            const submit = page.getByRole("button", { name: "Sign in", exact: true });
            await username.fill("private@example.com");
            return { taskComplete: true, evidence: "dashboard" };
          `,
        },
        result: {
          operations: [
            { operation: "snapshot", ok: true },
            { operation: "click", ok: true },
          ],
          result: { taskComplete: true, evidence: "dashboard" },
        },
      }];

      const learned = learnBrowserSkillFromArtifacts({
        trace,
        finalState: { url: "https://accounts.example.com/dashboard/123456" },
      }, root);

      expect(learned?.hostname).toBe("accounts.example.com");
      const markdown = readFileSync(learned!.path, "utf8");
      expect(markdown).toContain('page.getByLabel("Username or Email", { exact: true })');
      expect(markdown).toContain('page.getByPlaceholder("Password", { exact: true })');
      expect(markdown).toContain('page.getByRole("button", { name: "Sign in", exact: true })');
      expect(markdown).not.toContain("private@example.com");
      expect(learnedBrowserSkillAttachments("Open accounts example", undefined, root)).toHaveLength(1);
      expect(learnedBrowserSkillAttachments("Continue in this tab", "https://accounts.example.com/login", root)).toHaveLength(1);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });

  test("does not learn from an unverified browser run", () => {
    const root = mkdtempSync(join(tmpdir(), "detach-browser-skills-"));
    try {
      const trace = [{
        id: "trace-2",
        command: "browser.execute_code",
        engine: "signed_in",
        startedAt: 1,
        durationMs: 10,
        ok: true,
        args: { code: 'return await page.getByRole("button", { name: "Login" }).click();' },
        result: { operations: [{ operation: "click", ok: true }], result: { clicked: true } },
      }] satisfies BrowserTraceEntry[];
      expect(learnBrowserSkillFromArtifacts({ trace, finalState: { url: "https://example.com/login" } }, root)).toBeUndefined();
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});
