import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import { cursorProviderCredentials } from "../runtime/providers/CursorProviderCredentials";
import type { AgentAdapter, AgentStreamCallbacks } from "./AgentAdapter";
import { runACPAgent } from "./ACPAgentRunner";

export class CursorAdapter implements AgentAdapter {
  readonly id = "cursor" as const;
  readonly displayName = "Cursor";

  async isAvailable() {
    return Boolean(await findExecutable("cursor"));
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks) {
    return runACPAgent({
      request,
      callbacks,
      activity: "Starting Cursor",
      activityAgent: this.id,
      args: ["acp"],
      unavailableMessage: "Cursor CLI was not found. Install Cursor CLI and run 'cursor-agent login'.",
      timeoutEnvironmentVariable: "DETACH_CURSOR_TIMEOUT_MS",
      model: request.model?.trim(),
      modelSettings: request.modelSettings,
      authenticateMethodID: "cursor_login",
      prepare: async () => ({
        executable: await findExecutable("cursor"),
        env: cursorProviderCredentials.environment(),
        skipAuthenticate: Boolean(cursorProviderCredentials.apiKey || Bun.env.CURSOR_API_KEY?.trim()),
      }),
    });
  }
}
