import { describe, expect, test } from "bun:test";

import { CapabilityBroker } from "./CapabilityBroker";
import type { BrowserAutomation } from "../browser/BrowserAutomation";
import type { BrowserBridge } from "../browser/BrowserBridge";
import type { DesktopBridge } from "../desktop/DesktopBridge";
import type { SecretBridge } from "../secrets/SecretBridge";

describe("capability broker", () => {
  test("lists compact descriptors without loading operation schemas", async () => {
    const broker = createBroker();
    const capabilities = await broker.list();

    expect(capabilities.map((item) => item.id)).toEqual(["browser", "macos", "secrets"]);
    expect(capabilities.every((item) => !Object.hasOwn(item, "tools"))).toBe(true);
    expect(capabilities.find((item) => item.id === "browser")?.operationCount).toBe(1);
  });

  test("describes only the requested capability", async () => {
    const broker = createBroker();
    const description = await broker.describe("macos");

    expect(description.id).toBe("macos");
    expect(description.tools.length).toBeGreaterThan(1);
    expect(description.tools.some((tool) => tool.name === "detach_macos_snapshot")).toBe(true);
  });

  test("starts Browser lazily on the first broker invocation", async () => {
    const calls: string[] = [];
    let active = false;
    const browserAutomation = {
      getStatus: async () => ({ extensionConnected: true, runtimeConnected: true }),
      isTaskActive: () => active,
      beginTask: async () => { active = true; calls.push("begin"); },
      execute: async () => { calls.push("execute"); return { ok: true }; },
      endTask: async () => { active = false; calls.push("end"); },
      getArtifacts: () => ({ trace: [], screenshots: [] }),
    } as unknown as BrowserAutomation;
    const broker = createBroker(browserAutomation);

    broker.registerRun("run-1");
    expect(calls).toEqual([]);
    await broker.invoke({
      capabilityId: "browser",
      toolName: "detach_browser_execute",
      arguments: { code: "return 1" },
      runId: "run-1",
    });
    expect(calls).toEqual(["begin", "execute"]);
    await broker.endRun("run-1");
    expect(calls).toEqual(["begin", "execute", "end"]);
  });
});

function createBroker(browserAutomation = {
  getStatus: async () => ({ extensionConnected: true, runtimeConnected: true }),
  isTaskActive: () => false,
  beginTask: async () => undefined,
  execute: async () => ({ ok: true }),
  endTask: async () => undefined,
  getArtifacts: () => ({ trace: [], screenshots: [] }),
} as unknown as BrowserAutomation) {
  const browserBridge = {} as BrowserBridge;
  const desktopBridge = {
    getStatus: () => ({ appConnected: true }),
    execute: async () => ({ ok: true }),
  } as unknown as DesktopBridge;
  const secretBridge = {
    isAppConnected: () => true,
  } as unknown as SecretBridge;
  return new CapabilityBroker(browserAutomation, browserBridge, desktopBridge, secretBridge);
}
