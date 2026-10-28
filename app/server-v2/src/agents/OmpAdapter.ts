import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { AgentAdapter, AgentStreamCallbacks } from "./AgentAdapter";
import { runACPAgent } from "./ACPAgentRunner";

export class OmpAdapter implements AgentAdapter {
  readonly id = "omp" as const;
  readonly displayName = "Omp";

  async isAvailable() { return Boolean(await findExecutable(this.id)); }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks) {
    return runACPAgent({
      request, callbacks, activity: "Starting Omp", activityAgent: this.id,
      args: ["acp"], model: request.model?.trim(), modelSettings: request.modelSettings,
      env: { NO_COLOR: "1" },
      unavailableMessage: "Oh My Pi was not found. Install omp and sign in with /login, then restart Detach.",
      timeoutEnvironmentVariable: "DETACH_OMP_TIMEOUT_MS",
      prepare: async () => ({ executable: await findExecutable(this.id) }),
    });
  }
}
