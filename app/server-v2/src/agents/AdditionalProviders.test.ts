import { describe, expect, test } from "bun:test";
import { chmodSync, readFileSync } from "node:fs";
import { PiAdapter, buildPiArgs } from "./PiAdapter";
import { AmpAdapter, buildAmpArgs } from "./AmpAdapter";
import { OmpAdapter } from "./OmpAdapter";
import { AmpStream } from "./amp/AmpStream";
import { PiRPCProcess } from "./pi/PiRPCProcess";
import { piRunExtension, piMCPServerName } from "./pi/PiExtension";
import { answerPiUI } from "./pi/PiUI";
import { acpModelCatalog } from "./ACPModelCatalog";
import { createTempTextFile } from "./CliAdapterUtils";
import { discoverAdditionalAgents, piModels } from "../runtime/providers/AdditionalAgents";
import type { ChatRequest } from "../protocol/messages";

const request: ChatRequest = { type: "chat", text: "Review this task", agent: "pi", runId: "test-pi" };
const callbacks = { onActivity() {}, onChunk() {},
  async onQuestion() { return { answer: { answers: ["Mac app"] } }; }, async onPermission() { return true; } };

async function fixture<T>(provider: "pi" | "amp" | "omp", run: (path: string) => Promise<T>) {
  const file = createTempTextFile("detach-provider-fixture-", provider,
    readFileSync(new URL("./fixtures/ProviderFixture.ts", import.meta.url), "utf8"));
  chmodSync(file.path, 0o755);
  const key = `DETACH_${provider.toUpperCase()}_PATH`, previous = Bun.env[key];
  Bun.env[key] = file.path;
  try { return await run(file.path); }
  finally {
    if (previous === undefined) delete Bun.env[key]; else Bun.env[key] = previous;
    file.cleanup();
  }
}

describe("additional CLI providers", () => {
  test("Pi streams, waits for native questions/permissions, and finishes only when settled", async () => {
    await fixture("pi", async () => {
      const chunks: string[] = [];
      const sessions: string[] = [];
      const result = await new PiAdapter().run(request, { ...callbacks, onSession: (session) => sessions.push(session.id), onChunk: (text) => chunks.push(text) }).finished;
      expect(result.text).toBe("Hello\u2028world");
      expect(chunks.join("")).toBe(result.text);
      expect(sessions).toEqual(["pi-fixture", "pi-fixture"]);
      expect(buildPiArgs(request, "fixture")).not.toContain("--no-session");
    });
  });
  test("Pi cancellation settles a pending question without waiting on the user", async () => {
    await fixture("pi", async (command) => {
      let asked!: () => void; const waiting = new Promise<void>((resolve) => { asked = resolve; });
      const child = new PiRPCProcess({ command, args: [], cwd: process.cwd(), callbacks: {
        ...callbacks, onQuestion() { asked(); return new Promise(() => {}); },
      } });
      const finished = child.run("Work");
      await waiting; child.cancel();
      await expect(finished).rejects.toThrow("cancelled");
    });
  });
  test("Pi native confirmation fails closed without a permission callback", async () => {
    expect(await answerPiUI({ id: "p", method: "confirm", title: "Allow?" },
      { onActivity() {}, onChunk() {} })).toEqual({ type: "extension_ui_response", id: "p", confirmed: false });
  });
  test("Pi queues concurrent dialogs instead of replacing a pending question", async () => {
    await fixture("pi", async (command) => {
      let asked!: () => void, answer!: (value: { answer: { answers: string[] } }) => void;
      const waiting = new Promise<void>((resolve) => { asked = resolve; });
      let approvals = 0;
      const child = new PiRPCProcess({ command, args: [], cwd: process.cwd(), callbacks: {
        ...callbacks, onQuestion() { asked(); return new Promise((resolve) => { answer = resolve; }); },
        async onPermission() { approvals += 1; return true; },
      } });
      const finished = child.run("Work");
      await waiting; await Bun.sleep(25);
      expect(approvals).toBe(0);
      answer({ answer: { answers: ["Mac app"] } });
      await finished; expect(approvals).toBe(1);
    });
  });
  test("Pi paginates long native choice lists within the shared question contract", async () => {
    let page = 0;
    const response = await answerPiUI({ id: "many", method: "select", title: "Choose",
      options: ["A", "B", "C", "D", "E", "F", "G", "H"] }, { ...callbacks,
      async onQuestion(request) {
        expect(request.questions[0]!.options!.length).toBeLessThanOrEqual(6);
        return { answer: { answers: [page++ === 0 ? "More choices" : "H"] } };
      },
    });
    expect(response).toEqual({ type: "extension_ui_response", id: "many", value: "H" });
  });
  test("Pi attaches run-local MCP and guards shell commands without touching user config", () => {
    const extension = piRunExtension({ ...request, mcpServers: [{
      id: "tools", name: "Tools", enabled: true, transport: "stdio", command: "/safe/server", args: [],
      created_at: 0, updated_at: 0,
    }] }, "detach-test");
    expect(extension).toContain("registerMcpServer");
    expect(extension).toContain("ctx.ui.confirm");
    expect(extension).not.toContain("writeFile");
    expect(piMCPServerName(crypto.randomUUID(), 0).length).toBeLessThan(16);
    expect(buildPiArgs({ ...request, model: "provider/model" }, "/tmp/extension")).toContain("provider/model");
  });
  test("Amp uses a private MCP file, streams once, and preserves workspace/context/mode", async () => {
    await fixture("amp", async () => {
      const result = await new AmpAdapter().run({ ...request, agent: "amp", model: "high",
        workspacePath: process.cwd(), mcpServers: [{ id: "broker", name: "Broker", enabled: true,
          transport: "stdio", command: "/bin/echo", args: ["server"], env: { SECRET: "not-in-argv" },
          created_at: 0, updated_at: 0 }] }, callbacks).finished;
      const output = JSON.parse(result.text);
      expect(output.prompt).toContain(request.text);
      expect(output.mode).toBe("high"); expect(output.mcp).toEqual(["broker"]);
      expect(output.cwd).toBe(process.cwd());
      const args = buildAmpArgs(request, "/private/tmp/mcp.json");
      expect(args).toContain("/private/tmp/mcp.json");
      expect(args.join(" ")).not.toMatch(/allow-all|dangerously|SECRET|not-in-argv/);
    });
  });
  test("Amp ignores nested agent text and surfaces result errors", () => {
    const stream = new AmpStream(callbacks);
    stream.handle({ type: "assistant", parent_tool_use_id: "child", message: { content: [{ type: "text", text: "hidden" }] } });
    stream.handle({ type: "result", is_error: true, error: "Sign in required" });
    expect(stream.text).toBe(""); expect(stream.error).toBe("Sign in required");
  });
  test("Omp routes native approvals and applies provider-qualified model and thinking", async () => {
    await fixture("omp", async () => {
      const result = await new OmpAdapter().run({ ...request, agent: "omp", model: "provider/selected",
        modelSettings: { reasoningEffort: "high" } }, callbacks).finished;
      expect(JSON.parse(result.text)).toEqual({ modelSet: true, effortSet: true });
    });
  });
  test("Omp rejects an unapproved command", async () => {
    await fixture("omp", async () => {
      await expect(new OmpAdapter().run({ ...request, agent: "omp" },
        { ...callbacks, onPermission: async () => false }).finished).rejects.toThrow("declined to continue");
    });
  });
  test("Omp queues concurrent approvals until the previous decision is resolved", async () => {
    await fixture("omp", async () => {
      let asked!: () => void, decide!: (approved: boolean) => void, count = 0;
      const waiting = new Promise<void>((resolve) => { asked = resolve; });
      const run = new OmpAdapter().run({ ...request, agent: "omp" }, { ...callbacks,
        onPermission() {
          count += 1;
          if (count === 1) { asked(); return new Promise((resolve) => { decide = resolve; }); }
          return Promise.resolve(true);
        },
      });
      await waiting; await Bun.sleep(25);
      expect(count).toBe(1);
      decide(true); await run.finished; expect(count).toBe(2);
    });
  });
  test("all four advertise install guidance when missing, not fake models", async () => {
    const capabilities = await discoverAdditionalAgents(async () => undefined);
    expect(capabilities.map((item) => item.id)).toEqual(["cursor", "pi", "amp", "omp"]);
    expect(capabilities.every((item) => !item.installed && item.models.length === 0 && item.authHint)).toBe(true);
  });
  test("installed catalogs use native Pi/Omp model discovery and Amp mode identities", async () => {
    await fixture("pi", async (path) => {
      const [pi, amp, omp] = await Promise.all(["pi", "amp", "omp"].map(async (provider) =>
        (await discoverAdditionalAgents(async () => path, provider))[0]!));
      const capabilities = [pi, amp, omp];
      expect(capabilities.every((item) => item.installed)).toBe(true);
      expect(capabilities.map((item) => item.models.length)).toEqual([1, 4, 2]);
      expect(capabilities[0]?.defaultModel).toBe("provider/default");
      expect(capabilities[1]?.models.map((item) => item.id)).toEqual(["low", "medium", "high", "ultra"]);
      expect(capabilities[2]?.defaultModel).toBe("provider/default");
    });
  });
  test("provider catalogs retain concrete model IDs and reject malformed rows", () => {
    expect(piModels([{ provider: "custom", id: "model", name: "My model" }, {}])).toEqual([
      { id: "custom/model", displayName: "custom · My model" },
    ]);
    expect(acpModelCatalog({ configOptions: [{ id: "model", currentValue: "p/m",
      options: [{ name: "Provider", options: [{ value: "p/m", name: "Model" }] }] }] }))
      .toEqual({ models: [{ id: "p/m", displayName: "Model" }], defaultModel: "p/m" });
  });
});
