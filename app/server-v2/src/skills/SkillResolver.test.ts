import { describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, realpathSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

import { resolveSelectedSkillInstructions } from "./SkillResolver";

describe("selected skill resolution", () => {
  test("loads a skill from the Detach-managed workspace root", () => {
    const root = mkdtempSync(join(tmpdir(), "detach-managed-skills-"));
    const skillDirectory = join(root, "workspace", ".agents", "skills", "remote-review");
    mkdirSync(skillDirectory, { recursive: true });
    const skillPath = join(skillDirectory, "SKILL.md");
    writeFileSync(skillPath, "# Remote review\n\nUse the installed review guidance.");

    const instructions = resolveSelectedSkillInstructions([
      { id: skillPath, name: "Remote review", path: skillPath },
    ], [join(root, "workspace", ".agents", "skills")]);

    expect(instructions).toContain("Use the installed review guidance.");
  });

  test("loads a selected SKILL.md only from a trusted installed-skill root", () => {
    const root = mkdtempSync(join(tmpdir(), "detach-skills-"));
    const skillDirectory = join(root, "review");
    mkdirSync(skillDirectory);
    const skillPath = join(skillDirectory, "SKILL.md");
    writeFileSync(skillPath, "# Review\n\nReview code carefully.");

    const instructions = resolveSelectedSkillInstructions([
      { id: skillPath, name: "Review", path: skillPath },
    ], [root]);

    expect(instructions).toContain("Selected skill: Review");
    expect(instructions).toContain(`Skill directory: ${dirname(realpathSync(skillPath))}`);
    expect(instructions).toContain("Review code carefully.");
  });

  test("does not read an arbitrary file supplied by the client", () => {
    const root = mkdtempSync(join(tmpdir(), "detach-skills-"));
    const outside = join(tmpdir(), `detach-untrusted-${Date.now()}.md`);
    writeFileSync(outside, "not a skill");

    expect(resolveSelectedSkillInstructions([
      { id: outside, name: "Untrusted", path: outside },
    ], [root])).toBe("");
  });
});
