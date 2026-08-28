import type { AgentKind, ChatRequest } from "../protocol/messages";
import type { AgentRun, AgentStreamCallbacks } from "./AgentAdapter";
import { ACPAgentProcess } from "./ACPAgentProcess";
import { buildAgentPrompt, resolveWorkspace } from "./AgentPrompt";
import { withTimeout } from "./CliAdapterUtils";

interface PreparedACPAgent {
  executable?: string;
  model?: string;
  env?: Record<string, string | undefined>;
}

export interface ACPAgentRunOptions {
  request: ChatRequest;
  callbacks: AgentStreamCallbacks;
  activity: string;
  activityAgent: AgentKind;
  args: string[];
  unavailableMessage: string;
  timeoutEnvironmentVariable: string;
  model?: string;
  modelSettings?: ChatRequest["modelSettings"];
  env?: Record<string, string | undefined>;
  prepare: () => Promise<PreparedACPAgent>;
}

export function runACPAgent(options: ACPAgentRunOptions): AgentRun {
  let cancelled = false;
  let process: ACPAgentProcess | undefined;

  const finished = (async () => {
    options.callbacks.onActivity(options.activity);
    const prepared = await options.prepare();
    if (!prepared.executable) throw new Error(options.unavailableMessage);

    process = new ACPAgentProcess({
      command: prepared.executable,
      args: options.args,
      cwd: resolveWorkspace(options.request.workspacePath),
      env: prepared.env ?? options.env,
      mcpServers: options.request.mcpServers,
      model: prepared.model ?? options.model,
      modelSettings: options.modelSettings,
      activityAgent: options.activityAgent,
      callbacks: options.callbacks,
    });
    if (cancelled) process.cancel();

    const result = await withTimeout(
      process.run(buildAgentPrompt(options.request)),
      resolveACPTimeout(options.request.timeoutMs, options.timeoutEnvironmentVariable),
      () => {
        cancelled = true;
        process?.cancel();
      },
    );
    return { text: result.text };
  })();

  return {
    cancel() {
      cancelled = true;
      process?.cancel();
    },
    finished,
  };
}

function resolveACPTimeout(requested: number | undefined, environmentVariable: string) {
  const value = Number(
    requested
      || Bun.env[environmentVariable]
      || Bun.env.DETACH_AGENT_TIMEOUT_MS
      || 900_000,
  );
  return Number.isFinite(value)
    ? Math.max(30_000, Math.min(value, 3_600_000))
    : 900_000;
}
