import type { ChatRequest } from "../protocol/messages";
import type {
  HostedModelCapability,
  HostedModelSession,
} from "../hosted/HostedModelSessionManager";
import { HostedModelSessionManager } from "../hosted/HostedModelSessionManager";
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
 * Detach Cloud deliberately uses a distinct OpenCode configuration and a
 * short-lived model token. It must never read or overwrite a user's OpenCode
 * credentials, models, or plugins used by the standalone adapter above.
 */
export class HostedOpenCodeAdapter implements AgentAdapter {
  readonly id = "hosted" as const;
  readonly displayName = "Detach Cloud";

  constructor(private readonly hostedModels: HostedModelSessionManager) {}

  async isAvailable() {
    return this.hostedModels.isConfigured() && Boolean(await findExecutable("opencode"));
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun {
    return runOpenCodeACP({
      request,
      callbacks,
      activity: "Connecting to Detach Cloud",
      args: ["acp", "--pure"],
      modelSettings: request.modelSettings,
      unavailableMessage: "The bundled OpenCode harness is unavailable. Reinstall or update Detach.",
      prepare: async () => {
        const executable = await findExecutable("opencode");
        if (!executable) {
          throw new Error("The bundled OpenCode harness is unavailable. Reinstall or update Detach.");
        }

        const session = await this.hostedModels.session(request.model);
        const model = request.model?.trim() || session.defaultModel;
        const modelCapability = session.models.find((item) => item.id === model);
        if (!modelCapability) {
          throw new Error(`Detach Cloud model '${model}' is not available for this Detach build.`);
        }

        callbacks.onActivity(`Using ${modelCapability.displayName}`);
        return {
          executable,
          // ACP's model config value is provider-qualified. The hosted
          // session catalog IDs are intentionally provider-neutral; ACP
          // applies the selected reasoning effort through its separate
          // `effort` config option.
          model: hostedOpenCodeModelReference(model),
          env: {
            ...openCodeStateEnvironment(),
            DETACH_HOSTED_MODEL_TOKEN: session.token,
            OPENCODE_CONFIG_CONTENT: JSON.stringify(buildOpenCodeConfig(session, model)),
            OPENCODE_DISABLE_AUTOUPDATE: "true",
            NO_COLOR: "1",
          },
        };
      },
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
  const model = hostedOpenCodeModelReference(selectedModel);

  return {
    $schema: "https://opencode.ai/config.json",
    model,
    small_model: model,
    autoupdate: false,
    share: "disabled",
    provider: {
      "detach-hosted": {
        // The Detach control plane intentionally exposes only /v1/responses.
        // OpenCode documents @ai-sdk/openai as the Responses-capable provider;
        // @ai-sdk/openai-compatible would silently use /chat/completions.
        npm: "@ai-sdk/openai",
        name: "Detach Cloud",
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

export function hostedOpenCodeModelReference(selectedModel: string) {
  const model = selectedModel.trim();
  return model.startsWith("detach-hosted/") ? model : `detach-hosted/${model}`;
}

function openCodeModelConfig(model: HostedModelCapability) {
  const limit = model.contextWindow || model.maxOutputTokens
    ? {
        ...(model.contextWindow ? { context: model.contextWindow } : {}),
        ...(model.maxOutputTokens ? { output: model.maxOutputTokens } : {}),
      }
    : undefined;

  const reasoningEfforts = model.reasoningEfforts ?? [];
  const variants = Object.fromEntries(
    reasoningEfforts.map((effort) => [effort, {
      reasoningEffort: effort,
      // Keep the setting explicit at the request-body boundary as well. This
      // makes the hosted Responses bridge work with OpenCode provider package
      // versions that do not forward the generic reasoningEffort option.
      body: { reasoning: { effort } },
    }]),
  );

  return {
    name: model.displayName,
    ...(limit ? { limit } : {}),
    ...(Object.keys(variants).length > 0 ? { variants } : {}),
  };
}
