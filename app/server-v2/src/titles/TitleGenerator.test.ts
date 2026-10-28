import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { TitleGenerator } from "./TitleGenerator";
import { runProcess } from "../runtime/ProcessRunner";
import type { AgentKind } from "../protocol/messages";

const fixture = fileURLToPath(new URL("./fixtures/TitleCLI.ts", import.meta.url));
const expected = "Add Notch Keyboard Navigation";
const message = "Add keyboard navigation to my side notch";
const models = [{ id: "small-mini", displayName: "Mini" }];

describe("isolated provider title processes", () => {
  test("all standalone naming adapters spawn separate temporary processes and clean up", async () => {
    for (const agent of ["codex", "claude", "grok", "pi", "omp", "amp", "opencode"] as AgentKind[]) {
      let directory = "";
      const generator = new TitleGenerator({
        find: async () => process.execPath, catalog: async () => ({ models }),
        standardCodex: async () => true,
        run(options) {
          directory = options.cwd!;
          expect(options.env?.NO_COLOR).toBe("1");
          expect(options.args.join(" ")).not.toContain("workspace-main");
          return runProcess({ ...options, args: [fixture, ...options.args] });
        },
      });
      expect(await generator.generate({ agent, model: "small-mini", message })).toBe(expected);
      expect(directory).toContain("detach-title-");
      expect(existsSync(directory)).toBe(false);
    }
  });
  test("total deadline terminates a stuck child and leaves a usable queue", async () => {
    let calls = 0, directory = "";
    const generator = new TitleGenerator({
      find: async () => process.execPath, catalog: async () => ({ models }),
      timeoutMs: 150,
      run(options) {
        directory = options.cwd!;
        return runProcess({ ...options,
          args: [fixture, ...(calls++ === 0 ? ["--fixture-hang"] : []), ...options.args] });
      },
    });
    expect(await generator.generate({ agent: "claude", message })).toBeUndefined();
    // Process cleanup runs asynchronously after an overall deadline; give the killed process one event-loop turn.
    await Bun.sleep(30);
    expect(existsSync(directory)).toBe(false);
    expect(await generator.generate({ agent: "claude", message })).toBe(expected);
  });
  test("custom Codex backends never silently route title data through the default backend", async () => {
    let resolved = false;
    const generator = new TitleGenerator({
      standardCodex: async () => false, find: async () => { resolved = true; return process.execPath; },
    });
    expect(await generator.generate({ agent: "codex", message })).toBeUndefined();
    expect(resolved).toBe(false);
  });
});
