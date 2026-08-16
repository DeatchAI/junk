import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { AgentAdapter, AgentRun, AgentStreamCallbacks } from "./AgentAdapter";
import { ACPAgentProcess } from "./ACPAgentProcess";
import { buildAgentPrompt, resolveWorkspace } from "./AgentPrompt";
import { withTimeout } from "./CliAdapterUtils";
import { enabledMCPServers } from "./MCPConfig";

export class GrokAdapter implements AgentAdapter {
  readonly id = "grok" as const;
  readonly displayName = "Grok";

  async isAvailable() {
    return Boolean(await findExecutable("grok"));
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun {
    let cancelled = false;
    let process: ACPAgentProcess | undefined;
    let heartbeat: Timer | undefined;
    let lastActivityAt = Date.now();

    const activityCallbacks: AgentStreamCallbacks = {
      ...callbacks,
      onActivity(status, toolName) {
        lastActivityAt = Date.now();
        callbacks.onActivity(status, toolName);
      },
      onChunk(text) {
        lastActivityAt = Date.now();
        callbacks.onChunk(text);
      },
    };

    const finished = (async () => {
      const executable = await findExecutable("grok");
      if (!executable) {
        throw new Error("Grok CLI was not found. Install Grok Build and sign in or configure XAI_API_KEY, then restart Detach.");
      }

      activityCallbacks.onActivity("Starting Grok through ACP");
      const prompt = buildAgentPrompt(request);
      const cwd = resolveWorkspace(request.workspacePath);
      const mcpServerCount = enabledMCPServers(request.mcpServers).length;
      if (mcpServerCount > 0) {
        activityCallbacks.onActivity(`Injecting ${mcpServerCount} MCP server${mcpServerCount === 1 ? "" : "s"} into Grok`);
      }

      process = new ACPAgentProcess({
        command: executable,
        args: buildGrokACPArgs(request),
        cwd,
        env: {
          NO_COLOR: "1",
          GROK_CURSOR_MCPS_ENABLED: "false",
          GROK_CLAUDE_MCPS_ENABLED: "false",
        },
        mcpServers: request.mcpServers,
        activityAgent: "grok",
        callbacks: activityCallbacks,
      });

      activityCallbacks.onActivity("Thinking…");
      heartbeat = setInterval(() => {
        if (cancelled) return;
        if (Date.now() - lastActivityAt >= 15_000) {
          callbacks.onActivity("Working…");
        }
      }, 15_000);

      try {
        return await withTimeout(
          process.run(prompt),
          resolveAgentTimeout(request.timeoutMs, Bun.env.DETACH_GROK_TIMEOUT_MS),
          () => {
            cancelled = true;
            process?.cancel();
          }
        );
      } catch (error) {
        const stderr = process.getStderr();
        if (stderr && error instanceof Error && !error.message.trim()) {
          throw new Error(stderr);
        }
        throw error;
      }
    })();

    const cleanup = () => {
      if (heartbeat) clearInterval(heartbeat);
    };
    finished.then(cleanup, cleanup);

    return {
      cancel() {
        cancelled = true;
        if (heartbeat) clearInterval(heartbeat);
        process?.cancel();
      },
      finished,
    };
  }
}

function resolveAgentTimeout(requested: number | undefined, agentOverride: string | undefined) {
  const value = Number(requested || agentOverride || Bun.env.DETACH_AGENT_TIMEOUT_MS || 900_000);
  return Number.isFinite(value) ? Math.max(30_000, Math.min(value, 3_600_000)) : 900_000;
}

export function buildGrokACPArgs(request: ChatRequest) {
  const args = ["agent", "--no-leader"];

  if (request.model?.trim()) {
    args.push("--model", request.model.trim());
  }

  const reasoningEffort = request.modelSettings?.reasoningEffort?.trim();
  if (reasoningEffort && ["low", "medium", "high"].includes(reasoningEffort)) {
    args.push("--reasoning-effort", reasoningEffort);
  }

  args.push("stdio");
  return args;
}
