import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { AgentAdapter, AgentRun, AgentStreamCallbacks } from "./AgentAdapter";
import { runACPAgent } from "./ACPAgentRunner";

export class OpenCodeAdapter implements AgentAdapter {
  readonly id = "opencode" as const;
  readonly displayName = "OpenCode";

  async isAvailable() {
    return Boolean(await findExecutable("opencode"));
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun {
    return runOpenCodeACP({
      request,
      callbacks,
      activity: "Starting OpenCode with your configured providers",
      args: ["acp"],
      model: request.model?.trim(),
      modelSettings: request.modelSettings,
      env: standaloneOpenCodeEnvironment(),
      unavailableMessage: "OpenCode is unavailable. Reinstall or update Detach.",
    });
  }
}

/**
 * Do not set XDG paths or OPENCODE_CONFIG_CONTENT here: standalone OpenCode
 * must inherit the same login, providers, model and plugins the user chose.
 */
export function standaloneOpenCodeEnvironment() {
  return {
    OPENCODE_DISABLE_AUTOUPDATE: "true",
    NO_COLOR: "1",
  };
}

interface OpenCodeRunOptions {
  request: ChatRequest;
  callbacks: AgentStreamCallbacks;
  activity: string;
  args: string[];
  model?: string;
  modelSettings?: ChatRequest["modelSettings"];
  env?: Record<string, string | undefined>;
  unavailableMessage: string;
  prepare?: () => Promise<{
    executable: string;
    model?: string;
    env?: Record<string, string | undefined>;
  }>;
}

function runOpenCodeACP(options: OpenCodeRunOptions): AgentRun {
  return runACPAgent({
    request: options.request,
    callbacks: options.callbacks,
    activity: options.activity,
    activityAgent: options.request.agent ?? "opencode",
    args: options.args,
    unavailableMessage: options.unavailableMessage,
    timeoutEnvironmentVariable: "DETACH_OPENCODE_TIMEOUT_MS",
    model: options.model,
    modelSettings: options.modelSettings,
    env: options.env,
    prepare: async () => options.prepare
      ? await options.prepare()
      : { executable: await findExecutable("opencode"), model: options.model, env: options.env },
  });
}
