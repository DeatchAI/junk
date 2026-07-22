import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import * as ts from "typescript";

import { defaultDataDir } from "../history/databasePath";
import type { SkillAttachment } from "../protocol/messages";
import type { BrowserTraceEntry } from "./BrowserAutomation";

interface BrowserLearningArtifacts {
  trace: BrowserTraceEntry[];
  finalState?: unknown;
}

interface BrowserRecipe {
  id: string;
  pathPattern: string;
  locators: string[];
  operations: string[];
  updatedAt: number;
}

interface BrowserSkillCatalog {
  version: 1;
  hostname: string;
  recipes: BrowserRecipe[];
}

export interface LearnedBrowserSkill {
  hostname: string;
  path: string;
  attachment: SkillAttachment;
}

const MAX_RECIPES = 12;
const MAX_LOCATORS_PER_RECIPE = 24;
const SAFE_OPERATIONS = new Set([
  "navigate", "open_tab", "snapshot", "query", "click", "key", "select", "upload_file", "wait", "get_active_tab",
]);

export function learnedBrowserSkillRoot() {
  return join(defaultDataDir(), "browser-skills");
}

export function learnedBrowserSkillAttachments(
  taskText: string,
  activeUrl?: string,
  root = learnedBrowserSkillRoot()
): SkillAttachment[] {
  let activeHostname = "";
  try {
    activeHostname = activeUrl ? normalizedHostname(new URL(activeUrl).hostname) : "";
  } catch {
    activeHostname = "";
  }
  const compactTask = taskText.toLocaleLowerCase().replace(/[^a-z0-9]+/g, "");

  let directories: string[] = [];
  try {
    directories = readdirSync(root, { withFileTypes: true }).filter((entry) => entry.isDirectory()).map((entry) => entry.name);
  } catch {
    return [];
  }

  return directories.flatMap((directory) => {
    const catalog = readCatalog(join(root, directory, "recipes.json"));
    if (!catalog) return [];
    const hostname = normalizedHostname(catalog.hostname);
    const domainToken = hostname.split(".").slice(0, -1).join("").replace(/[^a-z0-9]/g, "");
    const activeMatches = activeHostname === hostname || activeHostname.endsWith(`.${hostname}`) || hostname.endsWith(`.${activeHostname}`);
    const taskMatches = domainToken.length >= 4 && compactTask.includes(domainToken);
    if (!activeMatches && !taskMatches) return [];
    const path = join(root, directory, "SKILL.md");
    if (!existsSync(path)) return [];
    return [{
      id: `browser-skill:${hostname}`,
      name: `${hostname} learned browser steps`,
      path,
      summary: `Learned semantic navigation hints for ${hostname}`,
    }];
  });
}

export function learnBrowserSkillFromArtifacts(
  artifacts: BrowserLearningArtifacts,
  root = learnedBrowserSkillRoot()
): LearnedBrowserSkill | undefined {
  const successfulTrace = [...artifacts.trace].reverse().find((entry) => entry.ok && hasVerifiedCompletion(entry.result));
  if (!successfulTrace) return undefined;

  const url = finalUrl(artifacts) || lastHttpUrl(artifacts.trace);
  if (!url) return undefined;
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return undefined;
  }
  if (!/^https?:$/.test(parsed.protocol)) return undefined;

  const hostname = normalizedHostname(parsed.hostname);
  if (!hostname) return undefined;
  const locators = unique(artifacts.trace.flatMap((entry) => {
    const code = typeof entry.args?.code === "string" && entry.ok ? entry.args.code : "";
    return code ? extractStableLocators(code) : [];
  })).slice(0, MAX_LOCATORS_PER_RECIPE);
  if (locators.length === 0) return undefined;

  const pathPattern = safePathPattern(parsed.pathname);
  const operations = unique(artifacts.trace.flatMap((entry) => operationNames(entry.result))).filter((name) => SAFE_OPERATIONS.has(name));
  const directory = join(root, safePathSegment(hostname));
  const catalogPath = join(directory, "recipes.json");
  const existing = readCatalog(catalogPath);
  const recipe: BrowserRecipe = {
    id: pathPattern,
    pathPattern,
    locators,
    operations,
    updatedAt: Date.now(),
  };
  const recipes = [recipe, ...(existing?.recipes ?? []).filter((item) => item.id !== recipe.id)].slice(0, MAX_RECIPES);
  const catalog: BrowserSkillCatalog = { version: 1, hostname, recipes };
  mkdirSync(directory, { recursive: true });
  writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`, "utf8");
  const path = join(directory, "SKILL.md");
  writeFileSync(path, renderSkill(catalog), "utf8");

  return {
    hostname,
    path,
    attachment: {
      id: `browser-skill:${hostname}`,
      name: `${hostname} learned browser steps`,
      path,
      summary: `Learned semantic navigation hints for ${hostname}`,
    },
  };
}

function renderSkill(catalog: BrowserSkillCatalog) {
  const recipes = catalog.recipes.map((recipe) => `## Route ${recipe.pathPattern}

Stable semantic locators observed in a verified successful run:
${recipe.locators.map((locator) => `- \`${escapeCode(locator)}\``).join("\n")}

Observed browser operation order:
${recipe.operations.length ? recipe.operations.map((operation, index) => `${index + 1}. ${operation}`).join("\n") : "1. Inspect, act, and verify with the stable locators above."}`).join("\n\n");

  return `---
name: learned-browser-${safePathSegment(catalog.hostname)}
description: Learned semantic browser navigation for ${catalog.hostname}. Generated only from verified successful Detach browser runs.
---

# ${catalog.hostname}

Use this skill when navigating ${catalog.hostname}. It is learned evidence, not a hardcoded site integration.

Rules:
- Revalidate a locator before acting when the page layout or route differs.
- Never store or replay typed values, credentials, uploaded file contents, or per-run user data.
- Use Detach Secrets for credentials. Pass the known submit ref into the secure-fill call so fill, submit, and navigation evidence happen atomically.
- Mark a browser program complete only after direct evidence by returning \`{ taskComplete: true, evidence: ... }\`.

${recipes}
`;
}

function extractStableLocators(code: string) {
  const source = ts.createSourceFile("learned-browser-task.ts", code, ts.ScriptTarget.ES2022, true, ts.ScriptKind.TS);
  const locators: string[] = [];
  const visit = (node: ts.Node) => {
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression)) {
      const method = node.expression.name.text;
      if (["getByLabel", "getByPlaceholder"].includes(method)) {
        const value = literalString(node.arguments[0]);
        if (safeLocatorText(value)) locators.push(`page.${method}(${JSON.stringify(value)}, { exact: true })`);
      } else if (method === "getByRole") {
        const role = literalString(node.arguments[0]);
        const options = objectLiteralStrings(node.arguments[1]);
        if (safeLocatorText(role) && safeLocatorText(options.name)) {
          locators.push(`page.getByRole(${JSON.stringify(role)}, { name: ${JSON.stringify(options.name)}, exact: true })`);
        }
      } else if (method === "locator") {
        const selector = literalString(node.arguments[0]);
        if (safeSelector(selector)) locators.push(`page.locator(${JSON.stringify(selector)})`);
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(source);
  return unique(locators);
}

function hasVerifiedCompletion(result: unknown) {
  const record = asRecord(result);
  const completion = asRecord(record.result);
  return completion.taskComplete === true;
}

function operationNames(result: unknown) {
  const operations = asRecord(result).operations;
  if (!Array.isArray(operations)) return [];
  return operations.flatMap((value) => {
    const operation = asRecord(value);
    return operation.ok === true && typeof operation.operation === "string" ? [operation.operation] : [];
  });
}

function finalUrl(artifacts: BrowserLearningArtifacts) {
  const url = asRecord(artifacts.finalState).url;
  return typeof url === "string" && /^https?:\/\//.test(url) ? url : undefined;
}

function lastHttpUrl(trace: BrowserTraceEntry[]) {
  const urls = trace.flatMap((entry) => {
    const code = typeof entry.args?.code === "string" ? entry.args.code : "";
    return code.match(/https?:\/\/[^\s"'`)>]+/g) ?? [];
  });
  return urls.at(-1);
}

function readCatalog(path: string): BrowserSkillCatalog | undefined {
  try {
    const value = JSON.parse(readFileSync(path, "utf8")) as BrowserSkillCatalog;
    if (value.version !== 1 || typeof value.hostname !== "string" || !Array.isArray(value.recipes)) return undefined;
    return value;
  } catch {
    return undefined;
  }
}

function objectLiteralStrings(node: ts.Expression | undefined) {
  const result: Record<string, string> = {};
  if (!node || !ts.isObjectLiteralExpression(node)) return result;
  for (const property of node.properties) {
    if (!ts.isPropertyAssignment(property)) continue;
    const key = ts.isIdentifier(property.name) || ts.isStringLiteralLike(property.name) ? property.name.text : "";
    const value = literalString(property.initializer);
    if (key && value) result[key] = value;
  }
  return result;
}

function literalString(node: ts.Expression | undefined) {
  return node && ts.isStringLiteralLike(node) ? node.text : undefined;
}

function safeLocatorText(value?: string): value is string {
  return Boolean(
    value
    && value.length <= 160
    && !/[\n\r]/.test(value)
    && !/(ignore|disregard).{0,32}(instruction|prompt)|system\s+(message|prompt)|you are (chatgpt|an ai)|call\s+(this\s+)?tool/i.test(value)
  );
}

function safeSelector(value?: string): value is string {
  if (!safeLocatorText(value)) return false;
  return !/\bvalue\s*=|data:|javascript:|[a-z0-9_-]{48,}/i.test(value);
}

function safePathPattern(pathname: string) {
  const segments = pathname.split("/").filter(Boolean).slice(0, 8).map((segment) => {
    let decoded = segment;
    try { decoded = decodeURIComponent(segment); } catch {}
    decoded = decoded.slice(0, 80);
    return /^\d{4,}$/.test(decoded) || /^[0-9a-f-]{24,}$/i.test(decoded) || decoded.length > 48 ? ":id" : decoded;
  });
  return `/${segments.join("/")}` || "/";
}

function normalizedHostname(value: string) {
  return value.toLocaleLowerCase().replace(/^www\./, "").replace(/[^a-z0-9.-]/g, "");
}

function safePathSegment(value: string) {
  return value.toLocaleLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "site";
}

function escapeCode(value: string) {
  return value.replace(/`/g, "\\`");
}

function unique(values: string[]) {
  return [...new Set(values)];
}

function asRecord(value: unknown): Record<string, any> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, any>;
}
