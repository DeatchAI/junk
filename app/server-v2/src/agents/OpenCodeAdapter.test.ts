import { describe, expect, test } from "bun:test";
import { mkdtemp, rm } from "node:fs/promises";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { resolve } from "node:path";

import { HostedModelSessionManager } from "../hosted/HostedModelSessionManager";
import {
  buildOpenCodeConfig,
  HostedOpenCodeAdapter,
  hostedOpenCodeModelReference,
  standaloneOpenCodeEnvironment,
} from "./OpenCodeAdapter";

describe("OpenCode hosted configuration", () => {
  test("qualifies hosted ACP model references", () => {
    expect(hostedOpenCodeModelReference("openai/gpt-5.6-luna")).toBe(
      "detach-hosted/openai/gpt-5.6-luna",
    );
  });

  test("keeps standalone OpenCode attached to the user's own configuration", () => {
    const environment = standaloneOpenCodeEnvironment();

    expect(environment).toEqual({
      OPENCODE_DISABLE_AUTOUPDATE: "true",
      NO_COLOR: "1",
    });
    expect(environment).not.toHaveProperty("OPENCODE_CONFIG_CONTENT");
    expect(environment).not.toHaveProperty("DETACH_HOSTED_MODEL_TOKEN");
    expect(environment).not.toHaveProperty("XDG_CONFIG_HOME");
  });

  test("pins the provider to the Detach proxy and reads only the scoped token from env", () => {
    const config = buildOpenCodeConfig({
      baseURL: "https://detach.example/api/v1",
      token: "must-not-be-written-to-config",
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
      defaultModel: "openai/gpt-5.6-terra",
      models: [{
        id: "openai/gpt-5.6-terra",
        displayName: "GPT-5.6 Terra",
        provider: "kie",
        contextWindow: 400000,
        maxOutputTokens: 128000,
        reasoningEfforts: ["none", "low", "high"],
      }],
    }, "openai/gpt-5.6-terra");

    expect(config.model).toBe("detach-hosted/openai/gpt-5.6-terra");
    expect(config.provider["detach-hosted"].npm).toBe("@ai-sdk/openai");
    expect(config.provider["detach-hosted"].options).toEqual({
      baseURL: "https://detach.example/api/v1",
      apiKey: "{env:DETACH_HOSTED_MODEL_TOKEN}",
    });
    expect(JSON.stringify(config)).not.toContain("must-not-be-written-to-config");
    expect(config.permission["*"]).toBe("ask");
    const provider = config.provider["detach-hosted"]!;
    expect(provider.models["openai/gpt-5.6-terra"]!.variants).toEqual({
      none: { reasoningEffort: "none", body: { reasoning: { effort: "none" } } },
      low: { reasoningEffort: "low", body: { reasoning: { effort: "low" } } },
      high: { reasoningEffort: "high", body: { reasoning: { effort: "high" } } },
    });
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
    let receivedReasoningEffort = "";
    let receivedPath = "";
    const gateway = Bun.serve({
      port: await availablePort(),
      hostname: "127.0.0.1",
      async fetch(request) {
        receivedPath = new URL(request.url).pathname;
        const body = await request.json() as {
          model?: string;
          reasoning?: { effort?: string };
        };
        receivedModel = body.model ?? "";
        receivedReasoningEffort = body.reasoning?.effort ?? "";
        const response = {
          id: "resp_detach_test",
          object: "response",
          created_at: Math.floor(Date.now() / 1_000),
          status: "completed",
          model: receivedModel,
          output: [{
            id: "msg_detach_test",
            type: "message",
            status: "completed",
            role: "assistant",
            content: [{
              type: "output_text",
              text: "ACP gateway OK",
              annotations: [],
            }],
          }],
          usage: { input_tokens: 10, output_tokens: 3, total_tokens: 13 },
        };
        const events = [
          {
            type: "response.created",
            response: { ...response, status: "in_progress", output: [], usage: null },
          },
          {
            type: "response.output_item.added",
            output_index: 0,
            item: {
              id: "msg_detach_test",
              type: "message",
              status: "in_progress",
              role: "assistant",
              content: [],
            },
          },
          {
            type: "response.content_part.added",
            item_id: "msg_detach_test",
            output_index: 0,
            content_index: 0,
            part: { type: "output_text", text: "", annotations: [] },
          },
          {
            type: "response.output_text.delta",
            item_id: "msg_detach_test",
            output_index: 0,
            content_index: 0,
            delta: "ACP gateway OK",
          },
          {
            type: "response.output_text.done",
            item_id: "msg_detach_test",
            output_index: 0,
            content_index: 0,
            text: "ACP gateway OK",
          },
          {
            type: "response.output_item.done",
            output_index: 0,
            item: response.output[0],
          },
          { type: "response.completed", response },
        ];
        return new Response(
          `${events.map((event) => `event: ${event.type}\ndata: ${JSON.stringify(event)}\n\n`).join("")}data: [DONE]\n\n`,
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
      fetcher: (async (_input: string | URL | Request, _init?: RequestInit) => Response.json({
        baseURL: `http://127.0.0.1:${gateway.port}/v1`,
        token: "short-lived-test-token",
        expiresAt: new Date(Date.now() + 60 * 60_000).toISOString(),
        defaultModel: "openai/gpt-5.6-terra",
        models: [{
          id: "openai/gpt-5.6-terra",
          displayName: "GPT-5.6 Terra",
          provider: "kie",
          contextWindow: 1_050_000,
          maxOutputTokens: 128_000,
          reasoningEfforts: ["low"],
        }],
      })) as unknown as typeof fetch,
    });
    manager.configure({
      endpoint: "http://127.0.0.1:9999",
      accessToken: "user-session-test-token",
    });

    try {
      const chunks: string[] = [];
      const run = new HostedOpenCodeAdapter(manager).run({
        type: "chat",
        text: "Reply exactly with: ACP gateway OK",
        workspacePath: workspace,
        model: "openai/gpt-5.6-terra",
        modelSettings: { reasoningEffort: "low" },
      }, {
        onActivity() {},
        onChunk(text) { chunks.push(text); },
        async onPermission() { return false; },
      });

      const result = await run.finished.catch((error) => {
        throw new Error(
          `OpenCode Responses handshake failed: ${error instanceof Error ? error.message : String(error)}`,
        );
      });
      expect(result).toEqual({ text: "ACP gateway OK" });
      expect(chunks.join("")).toBe("ACP gateway OK");
      expect(receivedModel).toBe("openai/gpt-5.6-terra");
      expect(receivedReasoningEffort).toBe("low");
      expect(receivedPath).toBe("/v1/responses");
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
