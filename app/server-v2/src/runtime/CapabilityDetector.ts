import type { AgentCapability, AgentModelCapability } from "../protocol/messages";
import type { AgentKind } from "../protocol/messages";
import type { HostedModelSessionManager } from "../hosted/HostedModelSessionManager";
import { runProcess } from "./ProcessRunner";

const homeExecutableDirs = Bun.env.HOME
  ? [
      `${Bun.env.HOME}/.grok/bin`,
      `${Bun.env.HOME}/.local/bin`,
      `${Bun.env.HOME}/.bun/bin`,
      `${Bun.env.HOME}/Applications/ChatGPT.app/Contents/Resources`,
      `${Bun.env.HOME}/Applications/Codex.app/Contents/Resources`,
    ]
  : [];

const commonExecutableDirs = [
  ...homeExecutableDirs,
  "/Applications/ChatGPT.app/Contents/Resources",
  "/Applications/Codex.app/Contents/Resources",
  "/opt/homebrew/bin",
  "/usr/local/bin",
  "/usr/bin",
  "/bin",
  "/usr/sbin",
  "/sbin",
];

export async function findExecutable(name: string): Promise<string | undefined> {
  if (name === "opencode") {
    const configured = Bun.env.DETACH_OPENCODE_PATH?.trim();
    if (configured && await Bun.file(configured).exists()) return configured;
  }

  const fromPath = await which(name);
  if (fromPath) return fromPath;

  for (const dir of commonExecutableDirs) {
    const candidate = `${dir}/${name}`;
    if (await Bun.file(candidate).exists()) {
      return candidate;
    }
  }

  return undefined;
}

export async function getCapabilities(
  defaultAgent: AgentKind,
  hostedModels?: HostedModelSessionManager,
): Promise<AgentCapability[]> {
  const [codexPath, claudePath, grokPath, openCodePath] = await Promise.all([
    findExecutable("codex"),
    findExecutable("claude"),
    findExecutable("grok"),
    findExecutable("opencode"),
  ]);
  const hostedConfigured = hostedModels?.isConfigured() === true;
  const [codexModels, grokCatalog, standaloneOpenCodeCatalog, openCodeCatalog] = await Promise.all([
    codexPath ? discoverCodexModels(codexPath) : Promise.resolve([]),
    grokPath ? discoverGrokModels(grokPath) : Promise.resolve({ models: [], defaultModel: undefined }),
    openCodePath
      ? discoverOpenCodeModels(openCodePath)
      : Promise.resolve({ models: [], error: undefined }),
    hostedConfigured
      ? hostedModels.capability()
        .then((catalog) => ({ ...catalog, error: undefined }))
        .catch((error) => ({
          models: [],
          defaultModel: undefined,
          error: error instanceof Error ? error.message : String(error),
        }))
      : Promise.resolve({ models: [], defaultModel: undefined, error: undefined }),
  ]);

  return [
    {
      id: "codex" as const,
      displayName: "Codex",
      installed: Boolean(codexPath),
      executablePath: codexPath,
      authHint: codexPath ? undefined : "Install Codex CLI and sign in with your OpenAI account.",
      models: codexModels,
    },
    {
      id: "claude" as const,
      displayName: "Claude",
      installed: Boolean(claudePath),
      executablePath: claudePath,
      authHint: claudePath ? undefined : "Install Claude Code and sign in with your Claude account.",
      models: claudePath ? claudeModels : [],
    },
    {
      id: "grok" as const,
      displayName: "Grok",
      installed: Boolean(grokPath),
      executablePath: grokPath,
      authHint: grokPath ? undefined : "Install Grok Build and sign in or configure XAI_API_KEY.",
      models: grokCatalog.models,
      defaultModel: grokCatalog.defaultModel,
    },
    {
      id: "opencode" as const,
      displayName: "OpenCode",
      installed: Boolean(openCodePath),
      executablePath: openCodePath,
      authHint: openCodePath
        ? standaloneOpenCodeCatalog.error
          ?? "Uses your existing OpenCode login and provider configuration."
        : "The OpenCode harness is missing. Reinstall or update Detach.",
      models: standaloneOpenCodeCatalog.models,
    },
    {
      id: "hosted" as const,
      displayName: "Detach Cloud",
      installed: Boolean(openCodePath && hostedConfigured && openCodeCatalog.models.length > 0),
      executablePath: openCodePath,
      authHint: hostedOpenCodeCapabilityHint(
        openCodePath,
        hostedConfigured,
        openCodeCatalog.error,
      ),
      models: openCodeCatalog.models,
      defaultModel: openCodeCatalog.defaultModel,
    },
  ].sort((a, b) => (a.id === defaultAgent ? -1 : b.id === defaultAgent ? 1 : 0));
}

function hostedOpenCodeCapabilityHint(
  executablePath: string | undefined,
  hostedConfigured: boolean,
  sessionError?: string,
) {
  if (!executablePath) return "The OpenCode harness is missing. Reinstall or update Detach.";
  if (!hostedConfigured) return "Sign in to Detach to use Detach Cloud models and credits.";
  return sessionError;
}

const claudeOpusReasoningEfforts = ["low", "medium", "high", "xhigh", "max"];
const claudeSonnetReasoningEfforts = ["low", "medium", "high", "max"];

const claudeModels: AgentModelCapability[] = [
  {
    id: "opus",
    displayName: "Opus",
    reasoningEfforts: claudeOpusReasoningEfforts,
    reasoningLabel: "Thinking",
  },
  {
    id: "sonnet",
    displayName: "Sonnet",
    reasoningEfforts: claudeSonnetReasoningEfforts,
    reasoningLabel: "Thinking",
  },
  { id: "haiku", displayName: "Haiku" },
];

async function discoverCodexModels(executable: string): Promise<AgentModelCapability[]> {
  try {
    const task = runProcess({ command: executable, args: ["debug", "models"] });
    const result = await resultWithTimeout(task, 5_000);
    if (result.exitCode !== 0) return [];
    const line = result.stdout.split("\n").find((item) => item.trim().startsWith("{"));
    if (!line) return [];
    const catalog = JSON.parse(line) as {
      models?: Array<{
        slug?: string;
        display_name?: string;
        visibility?: string;
        default_reasoning_level?: string;
        supported_reasoning_levels?: Array<{ effort?: string }>;
      }>;
    };
    return (catalog.models ?? [])
      .filter((model) => model.slug && model.visibility !== "hidden")
      .map((model) => {
        const reasoningEfforts = [...new Set(
          (model.supported_reasoning_levels ?? [])
            .map((level) => level.effort?.trim())
            .filter((effort): effort is string => Boolean(effort)),
        )];
        return {
          id: model.slug!,
          displayName: model.display_name || model.slug!,
          ...(reasoningEfforts.length > 0 ? { reasoningEfforts } : {}),
          ...(reasoningEfforts.length > 0 ? { reasoningLabel: "Effort" } : {}),
          ...(model.default_reasoning_level?.trim()
            ? { defaultReasoningEffort: model.default_reasoning_level.trim() }
            : {}),
        };
      });
  } catch {
    return [];
  }
}

async function discoverGrokModels(executable: string): Promise<{ models: AgentModelCapability[]; defaultModel?: string }> {
  try {
    const task = runProcess({ command: executable, args: ["models"] });
    const result = await resultWithTimeout(task, 5_000);
    const output = `${result.stdout}\n${result.stderr}`;
    const defaultModel = output.match(/Default model:\s*([^\s]+)/i)?.[1];
    const models = [...output.matchAll(/^\s*\*\s+([\w.-]+)(?:\s+\(default\))?\s*$/gm)]
      .map((match) => match[1])
      .filter((id): id is string => Boolean(id))
      .map((id) => ({
        id,
        displayName: humanizeModelId(id),
        ...grokReasoningCapability(id),
      }));
    const unique = [...new Map(models.map((model) => [model.id, model])).values()];
    if (defaultModel && !unique.some((model) => model.id === defaultModel)) {
      unique.unshift({
        id: defaultModel,
        displayName: humanizeModelId(defaultModel),
        ...grokReasoningCapability(defaultModel),
      });
    }
    return { models: unique, defaultModel };
  } catch {
    return { models: [], defaultModel: undefined };
  }
}

interface OpenCodeModelOutput {
  id?: unknown;
  providerID?: unknown;
  name?: unknown;
  status?: unknown;
  capabilities?: { toolcall?: unknown } | unknown;
  reasoning?: unknown;
  reasoning_options?: unknown;
}

/**
 * OpenCode emits one heading and one JSON object for each model when invoked
 * with `models --verbose`. The JSON catalog reflects the user's own providers
 * and login, so Detach must not maintain a second, stale model list.
 */
export async function discoverOpenCodeModels(
  executable: string,
): Promise<{ models: AgentModelCapability[]; error?: string }> {
  try {
    const task = runProcess({ command: executable, args: ["models", "--verbose"] });
    const result = await resultWithTimeout(task, 5_000);
    if (result.exitCode !== 0) {
      return {
        models: [],
        error: "OpenCode could not load its configured models. OpenCode will still use its default model.",
      };
    }
    return { models: parseOpenCodeModels(result.stdout) };
  } catch {
    return {
      models: [],
      error: "OpenCode could not load its configured models. OpenCode will still use its default model.",
    };
  }
}

export function parseOpenCodeModels(output: string): AgentModelCapability[] {
  const parsed = jsonObjects(output)
    .flatMap((value) => openCodeModelCapability(value));
  return [...new Map(parsed.map((model) => [model.id, model])).values()];
}

function openCodeModelCapability(value: unknown): AgentModelCapability[] {
  if (!value || typeof value !== "object" || Array.isArray(value)) return [];
  const model = value as OpenCodeModelOutput;
  const id = typeof model.id === "string" ? model.id.trim() : "";
  const providerID = typeof model.providerID === "string" ? model.providerID.trim() : "";
  const name = typeof model.name === "string" ? model.name.trim() : "";
  const isActive = model.status === undefined || model.status === "active";
  const supportsTools = Boolean(
    model.capabilities
      && typeof model.capabilities === "object"
      && !Array.isArray(model.capabilities)
      && (model.capabilities as { toolcall?: unknown }).toolcall === true,
  );
  if (!id || !providerID || !name || !isActive || !supportsTools) return [];

  const reasoningEfforts = openCodeReasoningEfforts(model.reasoning_options);
  return [{
    id: `${providerID}/${id}`,
    displayName: `${providerID} · ${name}`,
    ...(reasoningEfforts
      ? {
          reasoningEfforts,
          reasoningLabel: providerID.toLowerCase().startsWith("anthropic")
            ? "Thinking"
            : "Effort",
        }
      : {}),
  }];
}

function grokReasoningCapability(modelID: string): Pick<AgentModelCapability, "reasoningEfforts" | "reasoningLabel"> | Record<string, never> {
  const normalized = modelID.toLowerCase();
  if (normalized.includes("grok-4.5") || normalized.includes("reason")) {
    return { reasoningEfforts: ["low", "medium", "high"], reasoningLabel: "Effort" };
  }
  return {};
}

function openCodeReasoningEfforts(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const effortOption = value.find((option) => {
    if (!option || typeof option !== "object" || Array.isArray(option)) return false;
    return (option as { type?: unknown }).type === "effort";
  });
  if (!effortOption || typeof effortOption !== "object" || Array.isArray(effortOption)) return undefined;
  const values = (effortOption as { values?: unknown }).values;
  if (!Array.isArray(values)) return undefined;
  const efforts = [...new Set(values.filter((item): item is string => typeof item === "string" && Boolean(item.trim())).map((item) => item.trim()))];
  return efforts.length > 0 ? efforts : undefined;
}

function jsonObjects(output: string): unknown[] {
  const values: unknown[] = [];
  for (let start = output.indexOf("{"); start >= 0; start = output.indexOf("{", start + 1)) {
    const end = jsonObjectEnd(output, start);
    if (end === undefined) continue;
    try {
      values.push(JSON.parse(output.slice(start, end + 1)));
      start = end;
    } catch {
      // Ignore incidental JSON-like CLI output and continue scanning.
    }
  }
  return values;
}

function jsonObjectEnd(input: string, start: number): number | undefined {
  let depth = 0;
  let quoted = false;
  let escaped = false;
  for (let index = start; index < input.length; index += 1) {
    const character = input[index];
    if (quoted) {
      if (escaped) escaped = false;
      else if (character === "\\") escaped = true;
      else if (character === '"') quoted = false;
      continue;
    }
    if (character === '"') quoted = true;
    else if (character === "{") depth += 1;
    else if (character === "}" && --depth === 0) return index;
  }
  return undefined;
}

async function resultWithTimeout(
  task: ReturnType<typeof runProcess>,
  timeoutMs: number,
) {
  let timeout: Timer | undefined;
  try {
    return await Promise.race([
      task.finished,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => {
          task.cancel();
          reject(new Error("Timed out while loading OpenCode models."));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

function humanizeModelId(id: string) {
  return id.split("-").map((part) => part.length <= 3 ? part.toUpperCase() : `${part[0]?.toUpperCase() ?? ""}${part.slice(1)}`).join(" ");
}

async function which(name: string): Promise<string | undefined> {
  try {
    const run = runProcess({
      command: "/usr/bin/env",
      args: ["which", name],
    });
    const result = await run.finished;
    if (result.exitCode === 0) {
      const path = result.stdout.trim().split("\n")[0];
      return path || undefined;
    }
  } catch {
    return undefined;
  }

  return undefined;
}
