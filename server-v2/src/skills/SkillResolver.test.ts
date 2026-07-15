import { describe, expect, test } from "bun:test";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { resolveSelectedSkillInstructions } from "./SkillResolver";

describe("selected skill resolution", () => {
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
