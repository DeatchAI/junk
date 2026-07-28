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
  const [codexModels, grokCatalog, openCodeCatalog] = await Promise.all([
    codexPath ? discoverCodexModels(codexPath) : Promise.resolve([]),
    grokPath ? discoverGrokModels(grokPath) : Promise.resolve({ models: [], defaultModel: undefined }),
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
      displayName: "Hosted AI",
      installed: Boolean(openCodePath && hostedConfigured && openCodeCatalog.models.length > 0),
      executablePath: openCodePath,
      authHint: openCodeCapabilityHint(openCodePath, hostedConfigured, openCodeCatalog.error),
      models: openCodeCatalog.models,
      defaultModel: openCodeCatalog.defaultModel,
    },
  ].sort((a, b) => (a.id === defaultAgent ? -1 : b.id === defaultAgent ? 1 : 0));
}

function openCodeCapabilityHint(
  executablePath: string | undefined,
  hostedConfigured: boolean,
  sessionError?: string,
) {
  if (!executablePath) return "The OpenCode harness is missing. Reinstall or update Detach.";
  if (!hostedConfigured) return "Sign in to the hosted Detach app to use hosted models.";
  return sessionError;
}

const claudeModels: AgentModelCapability[] = [
  { id: "opus", displayName: "Opus" },
  { id: "sonnet", displayName: "Sonnet" },
  { id: "haiku", displayName: "Haiku" },
];

async function discoverCodexModels(executable: string): Promise<AgentModelCapability[]> {
  try {
    const result = await runProcess({ command: executable, args: ["debug", "models"] }).finished;
    if (result.exitCode !== 0) return [];
    const line = result.stdout.split("\n").find((item) => item.trim().startsWith("{"));
    if (!line) return [];
    const catalog = JSON.parse(line) as { models?: Array<{ slug?: string; display_name?: string; visibility?: string }> };
    return (catalog.models ?? [])
      .filter((model) => model.slug && model.visibility !== "hidden")
      .map((model) => ({ id: model.slug!, displayName: model.display_name || model.slug! }));
  } catch {
    return [];
  }
}

async function discoverGrokModels(executable: string): Promise<{ models: AgentModelCapability[]; defaultModel?: string }> {
  try {
    const result = await runProcess({ command: executable, args: ["models"] }).finished;
    const output = `${result.stdout}\n${result.stderr}`;
    const defaultModel = output.match(/Default model:\s*([^\s]+)/i)?.[1];
    const models = [...output.matchAll(/^\s*\*\s+([\w.-]+)(?:\s+\(default\))?\s*$/gm)]
      .map((match) => match[1])
      .filter((id): id is string => Boolean(id))
      .map((id) => ({ id, displayName: humanizeModelId(id) }));
    const unique = [...new Map(models.map((model) => [model.id, model])).values()];
    if (defaultModel && !unique.some((model) => model.id === defaultModel)) {
      unique.unshift({ id: defaultModel, displayName: humanizeModelId(defaultModel) });
    }
    return { models: unique, defaultModel };
  } catch {
    return { models: [], defaultModel: undefined };
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
