import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { resolve } from "node:path";

import { HostedModelSessionManager } from "../hosted/HostedModelSessionManager";
import { buildOpenCodeConfig, OpenCodeAdapter } from "./OpenCodeAdapter";

describe("OpenCode hosted configuration", () => {
  test("pins the provider to the Detach proxy and reads only the scoped token from env", () => {
    const config = buildOpenCodeConfig({
      baseURL: "https://detach.example/api/hosted-model/v1",
      token: "must-not-be-written-to-config",
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      defaultModel: "openai/gpt-5.6-terra",
      models: [{
        id: "openai/gpt-5.6-terra",
        displayName: "GPT-5.6 Terra",
        provider: "vercel",
        contextWindow: 400000,
        maxOutputTokens: 128000,
      }],
    }, "openai/gpt-5.6-terra");

    expect(config.model).toBe("detach-hosted/openai/gpt-5.6-terra");
    expect(config.provider["detach-hosted"].options).toEqual({
      baseURL: "https://detach.example/api/hosted-model/v1",
      apiKey: "{env:DETACH_HOSTED_MODEL_TOKEN}",
    });
    expect(JSON.stringify(config)).not.toContain("must-not-be-written-to-config");
    expect(config.permission["*"]).toBe("ask");
  });

  test("completes a real OpenCode ACP turn through the hosted proxy contract", async () => {
    const platformPackage = process.arch === "arm64"
      ? "opencode-darwin-arm64"
      : "opencode-darwin-x64";
    const executable = resolve(
      import.meta.dir,
      "../../node_modules",
      platformPackage,
      "bin",
      "opencode",
    );
    if (!await Bun.file(executable).exists()) return;

    let receivedModel = "";
    const gateway = Bun.serve({
      port: await availablePort(),
      hostname: "127.0.0.1",
      async fetch(request) {
        const body = await request.json() as { model?: string };
        receivedModel = body.model ?? "";
        const now = Math.floor(Date.now() / 1_000);
        const chunks = [
          {
            id: "chatcmpl-detach-test",
            object: "chat.completion.chunk",
            created: now,
            model: receivedModel,
            choices: [{
              index: 0,
              delta: { role: "assistant", content: "ACP gateway OK" },
              finish_reason: null,
            }],
          },
          {
            id: "chatcmpl-detach-test",
            object: "chat.completion.chunk",
            created: now,
            model: receivedModel,
            choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
            usage: { prompt_tokens: 10, completion_tokens: 3, total_tokens: 13 },
          },
        ];
        return new Response(
          `${chunks.map((chunk) => `data: ${JSON.stringify(chunk)}\n\n`).join("")}data: [DONE]\n\n`,
          { headers: { "content-type": "text/event-stream" } },
        );
      },
    });
    const workspace = await mkdtemp(`${tmpdir()}/detach-opencode-workspace-`);
    const state = await mkdtemp(`${tmpdir()}/detach-opencode-state-`);
    const previousExecutable = Bun.env.DETACH_OPENCODE_PATH;
    const previousState = Bun.env.DETACH_OPENCODE_DATA_DIR;
    Bun.env.DETACH_OPENCODE_PATH = executable;
    Bun.env.DETACH_OPENCODE_DATA_DIR = state;

    const manager = new HostedModelSessionManager({
      hostedMode: true,
      fetcher: (async (_input: string | URL | Request, _init?: RequestInit) => Response.json({
        baseURL: `http://127.0.0.1:${gateway.port}/v1`,
        token: "short-lived-test-token",
        expiresAt: new Date(Date.now() + 60 * 60_000).toISOString(),
        defaultModel: "openai/gpt-5.6-terra",
        models: [{
          id: "openai/gpt-5.6-terra",
          displayName: "GPT-5.6 Terra",
          provider: "vercel",
          contextWindow: 1_050_000,
          maxOutputTokens: 128_000,
        }],
      })) as unknown as typeof fetch,
    });
    manager.configure({
      endpoint: "http://127.0.0.1:9999",
      accessToken: "user-session-test-token",
    });

    try {
      const chunks: string[] = [];
      const run = new OpenCodeAdapter(manager).run({
        type: "chat",
        text: "Reply exactly with: ACP gateway OK",
        workspacePath: workspace,
        model: "openai/gpt-5.6-terra",
      }, {
        onActivity() {},
        onChunk(text) { chunks.push(text); },
        async onPermission() { return false; },
      });

      await expect(run.finished).resolves.toEqual({ text: "ACP gateway OK" });
      expect(chunks.join("")).toBe("ACP gateway OK");
      expect(receivedModel).toBe("openai/gpt-5.6-terra");
    } finally {
      gateway.stop(true);
      Bun.env.DETACH_OPENCODE_PATH = previousExecutable;
      Bun.env.DETACH_OPENCODE_DATA_DIR = previousState;
      await rm(workspace, { recursive: true, force: true });
      await rm(state, { recursive: true, force: true });
    }
  }, 30_000);
});

async function availablePort() {
  const server = createServer();
  await new Promise<void>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const address = server.address();
  const port = typeof address === "object" && address ? address.port : undefined;
  await new Promise<void>((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
  if (!port) throw new Error("Unable to allocate a local test port.");
  return port;
}
