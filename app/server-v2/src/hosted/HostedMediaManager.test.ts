import { describe, expect, test } from "bun:test";

import { HostedMediaManager } from "./HostedMediaManager";
import { HostedModelSessionManager } from "./HostedModelSessionManager";

describe("HostedMediaManager", () => {
  test("uses the scoped hosted token for models, creation, and polling", async () => {
    const requests: Array<{ url: string; authorization: string | null; method: string }> = [];
    const expiresAt = new Date(Date.now() + 60 * 60_000).toISOString();
    let pollCount = 0;
    const fetcher = (async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      requests.push({
        url,
        authorization: new Headers(init?.headers).get("authorization"),
        method: init?.method ?? "GET",
      });
      if (url.endsWith("/api/hosted-model")) {
        return Response.json({
          baseURL: "https://detach.example/api/v1",
          token: "scoped-model-token",
          expiresAt,
          defaultModel: "openai/gpt-5.6-terra",
          models: [{
            id: "openai/gpt-5.6-terra",
            displayName: "GPT-5.6 Terra",
            provider: "kie",
          }],
        });
      }
      if (url.endsWith("/media/models")) {
        return Response.json({
          models: [{
            id: "gpt-image-2",
            displayName: "GPT Image 2",
            kind: "image",
            aspectRatios: [{ id: "1:1", label: "1:1" }],
            resolutions: [{ id: "1K", label: "1K" }],
            supportsAudio: false,
            outputFormats: [{ id: "png", label: "png" }],
            defaults: { aspectRatio: "1:1", resolution: "1K", outputFormat: "png" },
            inputRoles: ["reference"],
            maxInputs: 16,
          }],
        });
      }
      if (url.endsWith("/media/jobs")) {
        return Response.json({ job: mediaJob("waiting") }, { status: 202 });
      }
      if (url.includes("/media/jobs/job-1")) {
        pollCount += 1;
        return Response.json({
          job: mediaJob(pollCount > 0 ? "succeeded" : "generating"),
        });
      }
      return new Response(null, { status: 404 });
    }) as typeof fetch;

    const sessions = new HostedModelSessionManager({ fetcher });
    sessions.configure({
      endpoint: "https://detach.example",
      accessToken: "supabase-token",
    });
    const manager = new HostedMediaManager(sessions, { pollIntervalMs: 1 });

    expect((await manager.models()).map((model) => model.id)).toEqual(["gpt-image-2"]);
    const created = await manager.create({
      requestKey: crypto.randomUUID(),
      model: "gpt-image-2",
      prompt: "A paper fox",
      config: { aspectRatio: "1:1", resolution: "1K", outputFormat: "png" },
      inputs: [],
    });
    const updates: string[] = [];
    const completed = await manager.waitForCompletion(created, (job) => updates.push(job.state));

    expect(completed.state).toBe("succeeded");
    expect(completed.assets[0]?.kind).toBe("image");
    expect(updates).toEqual(["waiting", "succeeded"]);
    expect(requests.slice(1).every((request) => request.authorization === "Bearer scoped-model-token")).toBe(true);
  });
});

function mediaJob(state: string) {
  return {
    id: "job-1",
    kind: "image",
    model: "gpt-image-2",
    state,
    progress: state === "succeeded" ? 100 : 0,
    config: { aspectRatio: "1:1", resolution: "1K" },
    quote: { kieCredits: "6", detachCredits: "3" },
    assets: state === "succeeded" ? [{
      id: "asset-1",
      kind: "image",
      mimeType: "image/png",
      url: "https://storage.example/generated.png",
    }] : [],
  };
}
