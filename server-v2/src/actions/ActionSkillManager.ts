import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import type { ActionDefinition, AgentActivityEvent, SkillAttachment } from "../protocol/messages";
import { defaultDataDir } from "../history/databasePath";

export interface ActionRunTraceEntry {
  status: string;
  toolName?: string;
  event?: AgentActivityEvent;
}

export interface LearnedActionSkill {
  path: string;
  version: number;
  attachment: SkillAttachment;
}

export function learnedActionSkillRoot() {
  return join(defaultDataDir(), "action-skills");
}

export function learnedActionSkillAttachment(action: ActionDefinition): SkillAttachment | undefined {
  if (!action.learnedSkillPath?.trim()) return undefined;
  if (!existsSync(action.learnedSkillPath)) return undefined;
  return {
    id: `action-skill:${action.id}`,
    name: `${action.name} learned steps`,
    path: action.learnedSkillPath,
    summary: "Learned runbook for faster future action runs",
  };
}

export function createLearnedActionSkill(
  action: ActionDefinition,
  trace: ActionRunTraceEntry[],
  assistantText: string
): LearnedActionSkill {
  const version = (action.learnedSkillVersion ?? 0) + 1;
  const dir = join(learnedActionSkillRoot(), safePathSegment(action.id));
  const path = join(dir, "SKILL.md");
  mkdirSync(dir, { recursive: true });

  writeFileSync(path, buildSkillMarkdown(action, trace, assistantText), "utf8");

  return {
    path,
    version,
    attachment: {
      id: `action-skill:${action.id}`,
      name: `${action.name} learned steps`,
      path,
      summary: "Learned runbook for faster future action runs",
    },
  };
}

function buildSkillMarkdown(action: ActionDefinition, trace: ActionRunTraceEntry[], assistantText: string) {
  const tools = unique(
    trace
      .map((entry) => entry.toolName || entry.event?.toolName)
      .filter((item): item is string => Boolean(item?.trim()))
  );
  const statuses = unique(
    trace
      .map((entry) => entry.event?.title || entry.status)
      .map((item) => item.trim())
      .filter(Boolean)
  ).slice(0, 18);

  return `# ${escapeMarkdownTitle(action.name)} Learned Steps

Use this skill when running the Detach action "${action.name}".

Primary objective:
${indent(action.prompt)}

Execution policy:
- Follow these learned steps first; do not rediscover the workflow from scratch.
- Prefer direct app automation, AppleScript, Shortcuts, or MCP commands before visual screen inspection.
- Use visual inspection only when a direct step fails or the target app is in an unexpected state.
- Do not ask the user for additional input unless the action cannot proceed.
- Never store per-run user content in this skill; use the current request context as the dynamic input.

Required capabilities:
${action.mcpServerIds?.length ? action.mcpServerIds.map((id) => `- MCP server: ${id}`).join("\n") : "- None recorded"}

Observed successful tool path:
${tools.length ? tools.map((tool) => `- ${tool}`).join("\n") : "- No named tools were reported"}

Successful run outline:
${statuses.length ? statuses.map((status, index) => `${index + 1}. ${status}`).join("\n") : "1. Run the action prompt directly with the selected capabilities."}

Completion signal:
${indent(summarizeAssistantText(assistantText))}
`;
}

function summarizeAssistantText(value: string) {
  const compact = value.replace(/\s+/g, " ").trim();
  if (!compact) return "The action completed successfully.";
  return compact.length > 500 ? `${compact.slice(0, 500)}...` : compact;
}

function indent(value: string) {
  const trimmed = value.trim();
  return trimmed ? trimmed.split("\n").map((line) => `- ${line}`).join("\n") : "- No prompt recorded.";
}

function unique(values: string[]) {
  return Array.from(new Set(values));
}

function safePathSegment(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "action";
}

function escapeMarkdownTitle(value: string) {
  return value.replace(/[#\n\r]/g, " ").trim() || "Action";
}
