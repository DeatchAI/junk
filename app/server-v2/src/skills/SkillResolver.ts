import { readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, isAbsolute, join, relative } from "node:path";

import type { SkillAttachment } from "../protocol/messages";
import { defaultDataDir } from "../history/databasePath";

const MAX_SKILL_CHARACTERS = 64_000;

export function defaultSkillRoots() {
  const home = homedir();
  return [
    join(home, ".codex", "skills"),
    join(home, ".agents", "skills"),
    join(defaultDataDir(), "action-skills"),
    join(defaultDataDir(), "browser-skills"),
  ];
}

/**
 * Loads only SKILL.md files that live below one of Detach's installed-skill
 * roots. The app sends a path for user choice, but the runtime remains the
 * trust boundary and ignores arbitrary local-file paths.
 */
export function resolveSelectedSkillInstructions(
  skills: SkillAttachment[] = [],
  roots = defaultSkillRoots()
) {
  const trustedRoots = roots.flatMap((root) => {
    try {
      return [realpathSync(root)];
    } catch {
      return [];
    }
  });

  const seen = new Set<string>();
  const sections: string[] = [];

  for (const skill of skills) {
    if (!skill.path?.trim() || basename(skill.path) !== "SKILL.md") continue;

    let skillPath: string;
    try {
      skillPath = realpathSync(skill.path);
    } catch {
      continue;
    }

    if (seen.has(skillPath) || !trustedRoots.some((root) => isWithin(skillPath, root))) {
      continue;
    }

    let contents: string;
    try {
      contents = readFileSync(skillPath, "utf8").trim();
    } catch {
      continue;
    }

    if (!contents) continue;
    seen.add(skillPath);
    const name = skill.name?.trim() || skillPath.split("/").at(-2) || "Installed skill";
    sections.push(`Selected skill: ${name}\n${contents.slice(0, MAX_SKILL_CHARACTERS)}`);
  }

  return sections.join("\n\n---\n\n");
}

function isWithin(path: string, root: string) {
  const relativePath = relative(root, path);
  return relativePath !== "" && !relativePath.startsWith(`..${"/"}`) && relativePath !== ".." && !isAbsolute(relativePath);
}
