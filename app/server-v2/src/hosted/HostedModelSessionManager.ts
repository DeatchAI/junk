import type { AgentModelCapability } from "../protocol/messages";

export interface HostedModelCapability extends AgentModelCapability {
  provider: string;
  contextWindow?: number;
  maxOutputTokens?: number;
}

export interface HostedModelSession {
  baseURL: string;
  token: string;
  expiresAt: string;
  defaultModel: string;
  models: HostedModelCapability[];
}

interface HostedModelSessionManagerOptions {
  fetcher?: typeof fetch;
}

/**
 * Exchanges the signed-in app session for a short-lived token that is scoped to
 * Detach Cloud model inference. The Supabase access token stays in this process and
 * is never inherited by OpenCode or any command the agent launches.
 */
export class HostedModelSessionManager {
  private readonly fetcher: typeof fetch;
  private endpoint?: string;
  private accessToken?: string;
  private cachedSession?: HostedModelSession;

  constructor(options: HostedModelSessionManagerOptions = {}) {
    this.fetcher = options.fetcher ?? fetch;
  }

  configure(input: { endpoint?: string; accessToken?: string }) {
    this.cachedSession = undefined;
    const endpoint = normalizeControlPlaneURL(input.endpoint);
    const accessToken = input.accessToken?.trim();
    if (!endpoint || !accessToken) {
      this.endpoint = undefined;
      this.accessToken = undefined;
      return;
    }

    this.endpoint = endpoint;
    this.accessToken = accessToken;
  }

  isConfigured() {
    return Boolean(this.endpoint && this.accessToken);
  }

  async models(): Promise<HostedModelCapability[]> {
    return (await this.session()).models;
  }

  async capability() {
    const session = await this.session();
    return {
      models: session.models,
      defaultModel: session.defaultModel,
    };
  }

  async session(selectedModel?: string): Promise<HostedModelSession> {
    if (!this.endpoint || !this.accessToken) {
      throw new Error("Sign in to Detach to use Detach Cloud models.");
    }

    const requestedModel = selectedModel?.trim();
    if (this.cachedSession && sessionIsReusable(this.cachedSession, requestedModel)) {
      return this.cachedSession;
    }

    const response = await this.fetcher(`${this.endpoint}/api/hosted-model`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${this.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        action: "session",
        model: requestedModel || undefined,
      }),
    });

    const payload = await response.json().catch(() => undefined) as
      | HostedModelSession
      | { error?: { message?: unknown } }
      | undefined;
    if (!response.ok) {
      const message = payload && "error" in payload && typeof payload.error?.message === "string"
        ? payload.error.message
        : `Detach Cloud model session failed with HTTP ${response.status}.`;
      throw new Error(message);
    }

    const session = parseHostedModelSession(payload);
    this.cachedSession = session;
    return session;
  }

  async authenticatedRequest(path: string, init: RequestInit = {}) {
    const request = async () => {
      const session = await this.session();
      return this.fetcher(`${session.baseURL}${path.startsWith("/") ? path : `/${path}`}`, {
        ...init,
        headers: {
          authorization: `Bearer ${session.token}`,
          ...init.headers,
        },
      });
    };
    let response = await request();
    if (response.status === 401) {
      this.cachedSession = undefined;
      response = await request();
    }
    return response;
  }
}

function normalizeControlPlaneURL(value: string | undefined) {
  const candidate = value?.trim();
  if (!candidate) return undefined;

  try {
    const url = new URL(candidate);
    const isLocalDevelopment = url.protocol === "http:"
      && (url.hostname === "127.0.0.1" || url.hostname === "localhost");
    if (url.protocol !== "https:" && !isLocalDevelopment) return undefined;
    return url.toString().replace(/\/$/, "");
  } catch {
    return undefined;
  }
}

function sessionIsReusable(session: HostedModelSession, requestedModel?: string) {
  const expiresAt = Date.parse(session.expiresAt);
  if (!Number.isFinite(expiresAt) || expiresAt - Date.now() < 5 * 60_000) return false;
  if (!requestedModel) return true;
  return session.models.some((model) => model.id === requestedModel);
}

function parseHostedModelSession(value: unknown): HostedModelSession {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Detach Cloud model control plane returned an invalid session.");
  }

  const input = value as Record<string, unknown>;
  const baseURL = typeof input.baseURL === "string" ? input.baseURL.trim() : "";
  const token = typeof input.token === "string" ? input.token.trim() : "";
  const expiresAt = typeof input.expiresAt === "string" ? input.expiresAt.trim() : "";
  const defaultModel = typeof input.defaultModel === "string" ? input.defaultModel.trim() : "";
  const models = Array.isArray(input.models)
    ? input.models.flatMap((model) => parseModel(model))
    : [];

  let parsedBaseURL: URL;
  try {
    parsedBaseURL = new URL(baseURL);
  } catch {
    throw new Error("Detach Cloud model control plane returned an invalid base URL.");
  }

  const isLocalDevelopment = parsedBaseURL.protocol === "http:"
    && (parsedBaseURL.hostname === "127.0.0.1" || parsedBaseURL.hostname === "localhost");
  if ((parsedBaseURL.protocol !== "https:" && !isLocalDevelopment)
      || !token
      || !Number.isFinite(Date.parse(expiresAt))
      || !defaultModel
      || models.length === 0
      || !models.some((model) => model.id === defaultModel)) {
    throw new Error("Detach Cloud model control plane returned an incomplete session.");
  }

  return {
    baseURL: parsedBaseURL.toString().replace(/\/$/, ""),
    token,
    expiresAt,
    defaultModel,
    models,
  };
}

function parseModel(value: unknown): HostedModelCapability[] {
  if (!value || typeof value !== "object" || Array.isArray(value)) return [];
  const input = value as Record<string, unknown>;
  const id = typeof input.id === "string" ? input.id.trim() : "";
  const displayName = typeof input.displayName === "string" ? input.displayName.trim() : "";
  const provider = typeof input.provider === "string" ? input.provider.trim() : "";
  if (!id || !displayName || !provider) return [];

  const contextWindow = positiveInteger(input.contextWindow);
  const maxOutputTokens = positiveInteger(input.maxOutputTokens);
  const reasoningEfforts = stringArray(input.reasoningEfforts);
  const reasoningLabel = typeof input.reasoningLabel === "string" ? input.reasoningLabel.trim() : "";
  return [{
    id,
    displayName,
    provider,
    ...(contextWindow ? { contextWindow } : {}),
    ...(maxOutputTokens ? { maxOutputTokens } : {}),
    ...(reasoningEfforts ? { reasoningEfforts } : {}),
    ...(reasoningLabel ? { reasoningLabel } : {}),
  }];
}

function stringArray(value: unknown) {
  if (!Array.isArray(value)) return undefined;
  const values = [...new Set(value.filter((item): item is string => typeof item === "string" && Boolean(item.trim())).map((item) => item.trim()))];
  return values.length > 0 ? values : undefined;
}

function positiveInteger(value: unknown) {
  return typeof value === "number" && Number.isInteger(value) && value > 0
    ? value
    : undefined;
}
