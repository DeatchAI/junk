import { describe, expect, test } from "bun:test";

import { HostedModelSessionManager } from "./HostedModelSessionManager";

describe("HostedModelSessionManager", () => {
  test("exchanges the user session for a scoped hosted-model token and caches it", async () => {
    const requests: Array<{ url: string; authorization: string | null; body: unknown }> = [];
    const expiresAt = new Date(Date.now() + 60 * 60_000).toISOString();
    const fetcher = (async (input: string | URL | Request, init?: RequestInit) => {
      requests.push({
        url: String(input),
        authorization: new Headers(init?.headers).get("authorization"),
        body: JSON.parse(String(init?.body)),
      });
      return Response.json({
        baseURL: "https://detach.example/api/v1",
        token: "scoped-model-token",
        expiresAt,
        defaultModel: "openai/gpt-5.6-terra",
        models: [{
          id: "openai/gpt-5.6-terra",
          displayName: "GPT-5.6 Terra",
          provider: "kie",
          contextWindow: 400000,
          maxOutputTokens: 128000,
          reasoningLabel: "Effort",
          reasoningEfforts: ["none", "low", "high"],
        }],
      });
    }) as typeof fetch;
    const manager = new HostedModelSessionManager({ fetcher });
    manager.configure({
      endpoint: "https://detach.example/",
      accessToken: "supabase-user-token",
    });

    const first = await manager.session("openai/gpt-5.6-terra");
    const second = await manager.session("openai/gpt-5.6-terra");

    expect(first.token).toBe("scoped-model-token");
    expect(first.models[0]?.reasoningLabel).toBe("Effort");
    expect(first.models[0]?.reasoningEfforts).toEqual(["none", "low", "high"]);
    expect(second).toBe(first);
    expect(requests).toEqual([{
      url: "https://detach.example/api/hosted-model",
      authorization: "Bearer supabase-user-token",
      body: { action: "session", model: "openai/gpt-5.6-terra" },
    }]);
  });

  test("does not accept an insecure remote control-plane URL", () => {
    const manager = new HostedModelSessionManager();
    manager.configure({
      endpoint: "http://detach.example",
      accessToken: "secret",
    });
    expect(manager.isConfigured()).toBe(false);
  });
});
