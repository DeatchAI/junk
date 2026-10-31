import type { AgentCapability, AgentModelCapability } from "../../protocol/messages";
import { ACPAgentProcess } from "../../agents/ACPAgentProcess";
import { PiRPCProcess } from "../../agents/pi/PiRPCProcess";
import { asStringRecord, getString, withTimeout } from "../../agents/CliAdapterUtils";
import { runProcess } from "../ProcessRunner";
import { AMP_MODES } from "../../agents/amp/AmpStream";

type Finder = (name: string) => Promise<string | undefined>;
const providers = [
  { id: "cursor", displayName: "Cursor", install: "Install Cursor CLI, then run cursor-agent login." },
  { id: "pi", displayName: "Pi", install: "Install Pi from pi.dev, then run pi and /login." },
  { id: "amp", displayName: "Amp", install: "Install Amp from ampcode.com, then run amp login." },
  { id: "omp", displayName: "Omp", install: "Install Oh My Pi from omp.sh, then run omp and /login." },
] as const;

export async function discoverAdditionalAgents(find: Finder, only?: string, cursorApiKey?: string): Promise<AgentCapability[]> {
  return await Promise.all(providers.filter((provider) => !only || provider.id === only).map(async (provider): Promise<AgentCapability> => {
    const executablePath = await find(provider.id);
    if (!executablePath) return { ...provider, installed: false, authHint: provider.install, models: [] };
    try {
      const catalog = provider.id === "cursor" ? await cursorCatalog(executablePath, cursorApiKey)
        : provider.id === "pi" ? await piCatalog(executablePath)
        : provider.id === "omp" ? await ompCatalog(executablePath)
        : { models: AMP_MODES.map((id) => ({ id, displayName: id[0]!.toUpperCase() + id.slice(1) })) };
      return { id: provider.id, displayName: provider.displayName, installed: true, executablePath, ...catalog,
        authHint: provider.id === "amp"
          ? "Uses your Amp login and native model routing. Questions use Detach's shared tools."
          : provider.id === "cursor"
            ? "Uses Cursor CLI ACP. Sign in with cursor-agent login or add a Cursor API key in Detach settings."
          : "Uses your existing provider credentials and configuration." };
    } catch {
      return { id: provider.id, displayName: provider.displayName, installed: true, executablePath, models: [],
        authHint: provider.id === "cursor"
          ? "Cursor could not load its model catalog. Sign in with cursor-agent login or check the saved API key."
          : `${provider.displayName} could not load its model catalog. It will use its configured default; check its terminal setup.` };
    }
  }));
}

async function piCatalog(command: string) {
  const child = new PiRPCProcess({
    command, args: ["--mode", "rpc", "--no-session", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes"],
    cwd: process.cwd(), callbacks: { onActivity() {}, onChunk() {} },
  });
  try {
    return await withTimeout((async () => {
      const available = asStringRecord(await child.request("get_available_models"));
      const state = asStringRecord(await child.request("get_state"));
      const model = asStringRecord(state?.model);
      return { models: piModels(available?.models),
        defaultModel: getString(model?.provider) && getString(model?.id)
          ? `${getString(model?.provider)}/${getString(model?.id)}` : undefined };
    })(), 5_000, () => child.cancel());
  } finally { child.dispose(); }
}

export function piModels(value: unknown): AgentModelCapability[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const model = asStringRecord(item);
    const provider = getString(model?.provider), id = getString(model?.id);
    if (!provider || !id) return [];
    return [{ id: `${provider}/${id}`, displayName: `${provider} · ${getString(model?.name) || id}` }];
  });
}

async function ompCatalog(command: string) {
  const child = new ACPAgentProcess({
    command, args: ["--no-session", "acp"], cwd: process.cwd(), activityAgent: "omp",
    callbacks: { onActivity() {}, onChunk() {} },
  });
  try { return await withTimeout(child.catalog(), 5_000, () => child.cancel()); }
  finally { child.cancel(); }
}

async function cursorCatalog(command: string, apiKey?: string) {
  const child = runProcess({ command, args: ["models"], env: { CURSOR_API_KEY: apiKey } });
  const result = await withTimeout(child.finished, 5_000, () => child.cancel());
  if (result.exitCode !== 0) throw new Error(result.stderr || "Cursor could not list its available models.");
  const models = cursorModels(`${result.stdout}\n${result.stderr}`);
  return { models };
}

function cursorModels(output: string): AgentModelCapability[] {
  const ansi = /\u001b\[[0-?]*[ -/]*[@-~]/g;
  const models = new Map<string, AgentModelCapability>();
  for (const line of output.replace(ansi, "").split(/\r?\n/)) {
    const match = line.trim().match(/^(?:[-*]\s*)?(\S+)\s+-\s+(.+?)\s*$/);
    if (match && !models.has(match[1]!)) {
      models.set(match[1]!, { id: match[1]!, displayName: match[2]! });
    }
  }
  return [...models.values()];
}
