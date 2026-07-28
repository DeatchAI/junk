import type { ChatRequest } from "../protocol/messages";
import type {
  HostedModelCapability,
  HostedModelSession,
} from "../hosted/HostedModelSessionManager";
import { HostedModelSessionManager } from "../hosted/HostedModelSessionManager";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { AgentAdapter, AgentRun, AgentStreamCallbacks } from "./AgentAdapter";
import { buildAgentPrompt, resolveWorkspace } from "./AgentPrompt";
import { withTimeout } from "./CliAdapterUtils";
import { ACPAgentProcess } from "./ACPAgentProcess";

export class OpenCodeAdapter implements AgentAdapter {
  readonly id = "opencode" as const;
  readonly displayName = "Hosted AI";

  constructor(private readonly hostedModels: HostedModelSessionManager) {}

  async isAvailable() {
    return this.hostedModels.isConfigured() && Boolean(await findExecutable("opencode"));
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun {
    let cancelled = false;
    let process: ACPAgentProcess | undefined;

    const finished = (async () => {
      const executable = await findExecutable("opencode");
      if (!executable) {
        throw new Error("The bundled OpenCode harness is unavailable. Reinstall or update Detach.");
      }

      callbacks.onActivity("Connecting to hosted models");
      const session = await this.hostedModels.session(request.model);
      const model = request.model?.trim() || session.defaultModel;
      const modelCapability = session.models.find((item) => item.id === model);
      if (!modelCapability) {
        throw new Error(`Hosted model '${model}' is not available for this Detach build.`);
      }

      process = new ACPAgentProcess({
        command: executable,
        args: ["acp", "--pure"],
        cwd: resolveWorkspace(request.workspacePath),
        env: {
          ...openCodeStateEnvironment(),
          DETACH_HOSTED_MODEL_TOKEN: session.token,
          OPENCODE_CONFIG_CONTENT: JSON.stringify(buildOpenCodeConfig(session, model)),
          OPENCODE_DISABLE_AUTOUPDATE: "true",
          NO_COLOR: "1",
        },
        mcpServers: request.mcpServers,
        callbacks,
      });

      callbacks.onActivity(`Using ${modelCapability.displayName}`);
      const result = await withTimeout(
        process.run(buildAgentPrompt(request)),
        resolveOpenCodeTimeout(request.timeoutMs),
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
      finished: finished.then((result) => cancelled ? { text: result.text } : result),
    };
  }
}

function openCodeStateEnvironment(): Record<string, string | undefined> {
  const configured = Bun.env.DETACH_OPENCODE_DATA_DIR?.trim();
  const root = configured || (Bun.env.HOME
    ? `${Bun.env.HOME}/Library/Application Support/Detach/OpenCode`
    : undefined);
  if (!root) return {};

  return {
    XDG_DATA_HOME: `${root}/data`,
    XDG_CONFIG_HOME: `${root}/config`,
    XDG_CACHE_HOME: `${root}/cache`,
    XDG_STATE_HOME: `${root}/state`,
  };
}

export function buildOpenCodeConfig(session: HostedModelSession, selectedModel: string) {
  const models = Object.fromEntries(session.models.map((model) => [
    model.id,
    openCodeModelConfig(model),
  ]));
  const model = `detach-hosted/${selectedModel}`;

  return {
    $schema: "https://opencode.ai/config.json",
    model,
    small_model: model,
    autoupdate: false,
    share: "disabled",
    provider: {
      "detach-hosted": {
        npm: "@ai-sdk/openai-compatible",
        name: "Detach Hosted",
        options: {
          baseURL: session.baseURL,
          apiKey: "{env:DETACH_HOSTED_MODEL_TOKEN}",
        },
        models,
      },
    },
    permission: {
      "*": "ask",
      read: "allow",
      glob: "allow",
      grep: "allow",
      list: "allow",
      lsp: "allow",
      todowrite: "allow",
      external_directory: "ask",
      doom_loop: "ask",
    },
  };
}

function openCodeModelConfig(model: HostedModelCapability) {
  const limit = model.contextWindow || model.maxOutputTokens
    ? {
        ...(model.contextWindow ? { context: model.contextWindow } : {}),
        ...(model.maxOutputTokens ? { output: model.maxOutputTokens } : {}),
      }
    : undefined;

  return {
    name: model.displayName,
    ...(limit ? { limit } : {}),
  };
}

function resolveOpenCodeTimeout(requested: number | undefined) {
  const value = Number(
    requested
      || Bun.env.DETACH_OPENCODE_TIMEOUT_MS
      || Bun.env.DETACH_AGENT_TIMEOUT_MS
      || 900_000,
  );
  return Number.isFinite(value)
    ? Math.max(30_000, Math.min(value, 3_600_000))
    : 900_000;
}
