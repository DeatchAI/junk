import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { AgentAdapter, AgentRun, AgentStreamCallbacks } from "./AgentAdapter";
import { runACPAgent } from "./ACPAgentRunner";

export class FxAdapter implements AgentAdapter {
  readonly id = "fx" as const;
  readonly displayName = "fx";

  async isAvailable() {
    return Boolean(await findExecutable("fx"));
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun {
    return runACPAgent({
      request,
      callbacks,
      activity: "Starting fx",
      activityAgent: "fx",
      args: ["acp"],
      unavailableMessage: "fx was not found. Install fx, run 'fx login', then restart Detach.",
      timeoutEnvironmentVariable: "DETACH_FX_TIMEOUT_MS",
      model: request.model?.trim(),
      modelSettings: request.modelSettings,
      env: fxEnvironment(),
      prepare: async () => ({ executable: await findExecutable("fx") }),
    });
  }
}

export function fxEnvironment() {
  return {
    FX_AUTO_UPGRADE: "0",
    FX_PERMISSION_MODE: "ask",
    FX_SOUND: "off",
    NO_COLOR: "1",
  };
}
