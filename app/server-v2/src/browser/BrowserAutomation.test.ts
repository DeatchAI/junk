import { describe, expect, test } from "bun:test";

import { BrowserAutomation } from "./BrowserAutomation";
import { BrowserBridge } from "./BrowserBridge";

class MockSocket {
  messages: string[] = [];
  send(message: string) {
    this.messages.push(message);
  }
}

describe("shared P0 browser routing", () => {
  test("reports the browser harness version for benchmark preflight", async () => {
    const browser = new BrowserAutomation(new BrowserBridge());
    expect(await browser.getStatus()).toMatchObject({ harnessVersion: "0.3.5" });
  });

  test("partial mode changes preserve Power browser options", () => {
    const browser = new BrowserAutomation(new BrowserBridge());
    browser.updateSettings({ mode: "power", headless: true, viewportWidth: 1440, cdpUrl: " ws://localhost:9222/devtools/browser/test " });
    browser.updateSettings({ mode: "signed_in" });

    expect(browser.getSettings()).toMatchObject({
      mode: "signed_in",
      headless: true,
      viewportWidth: 1440,
      cdpUrl: "ws://localhost:9222/devtools/browser/test",
    });
  });

  test("keeps signed-in commands task-scoped and records structured traces", async () => {
    const bridge = new BrowserBridge();
    const socket = new MockSocket();
    bridge.attachNativeSocket(socket);
    bridge.handleNativeMessage(JSON.stringify({ type: "event", event: "extension.ready" }));
    const browser = new BrowserAutomation(bridge);

    const begin = browser.beginTask("run-1");
    expect(JSON.parse(socket.messages[0] ?? "{}")).toMatchObject({
      command: "browser.begin_task",
      payload: { runId: "run-1", isolated: false },
    });
    respond(bridge, socket.messages[0], { isolated: true, windowId: 7 });
    await begin;

    const command = browser.execute({ command: "browser.navigate", payload: { url: "https://example.com" } }, "run-1");
    await Bun.sleep(0);
    const sent = JSON.parse(socket.messages[1] ?? "{}") as { payload?: Record<string, unknown> };
    expect(sent.payload?.runId).toBe("run-1");
    respond(bridge, socket.messages[1], { url: "https://example.com", status: "complete" });
    await Bun.sleep(0);
    respond(bridge, socket.messages[2], { format: "jpeg", dataUrl: "data:image/jpeg;base64,aW1hZ2U=" });

    await expect(command).resolves.toMatchObject({
      url: "https://example.com",
      _detach: { engine: "signed_in" },
    });
    expect(browser.getArtifacts("run-1").trace).toHaveLength(1);
    expect(browser.getArtifacts("run-1").screenshots).toEqual(["aW1hZ2U="]);
    expect(browser.getArtifacts("run-1").trace[0]).toMatchObject({
      command: "browser.navigate",
      ok: true,
      engine: "signed_in",
    });
  });

  test("runs the same browser program through Signed-in Chrome primitives", async () => {
    const bridge = new BrowserBridge();
    const socket = new MockSocket();
    bridge.attachNativeSocket(socket);
    bridge.handleNativeMessage(JSON.stringify({ type: "event", event: "extension.ready" }));
    const browser = new BrowserAutomation(bridge);

    const begin = browser.beginTask("run-code");
    await waitForMessages(socket, 1);
    respond(bridge, socket.messages[0], { isolated: true, windowId: 9 });
    await begin;

    const execution = browser.execute({
      command: "browser.execute_code",
      payload: { code: 'await page.goto("https://example.com"); return "done";' },
    }, "run-code");
    await waitForMessages(socket, 2);
    expect(JSON.parse(socket.messages[1] ?? "{}")).toMatchObject({
      command: "browser.navigate",
      payload: { runId: "run-code", url: "https://example.com" },
    });
    respond(bridge, socket.messages[1], { url: "https://example.com", status: "complete" });

    await waitForMessages(socket, 3);
    respond(bridge, socket.messages[2], { events: [{ type: "navigation", url: "https://example.com" }] });
    await waitForMessages(socket, 4);
    respond(bridge, socket.messages[3], { format: "jpeg", dataUrl: "data:image/jpeg;base64,aW1hZ2U=" });

    await expect(execution).resolves.toMatchObject({
      result: "done",
      operations: [{ operation: "navigate", ok: true }],
      events: [{ type: "navigation", url: "https://example.com" }],
      _detach: { engine: "signed_in" },
    });
  });

  test("routes live locator verification through the Signed-in Chrome task", async () => {
    const bridge = new BrowserBridge();
    const socket = new MockSocket();
    bridge.attachNativeSocket(socket);
    bridge.handleNativeMessage(JSON.stringify({ type: "event", event: "extension.ready" }));
    const browser = new BrowserAutomation(bridge);

    const begin = browser.beginTask("run-live-query");
    await waitForMessages(socket, 1);
    respond(bridge, socket.messages[0], { isolated: true, windowId: 11 });
    await begin;

    const execution = browser.execute({
      command: "browser.execute_code",
      payload: { code: 'return await page.ref("email-ref").inputValue();' },
    }, "run-live-query");
    await waitForMessages(socket, 2);
    expect(JSON.parse(socket.messages[1] ?? "{}")).toMatchObject({
      command: "browser.query",
      payload: { runId: "run-live-query", ref: "email-ref", kind: "inputValue" },
    });
    respond(bridge, socket.messages[1], { value: "nonlatin@example.com", matched: true });
    await waitForMessages(socket, 3);
    respond(bridge, socket.messages[2], { events: [] });

    await expect(execution).resolves.toMatchObject({
      result: "nonlatin@example.com",
      operations: [{ operation: "query", ok: true }],
      _detach: { engine: "signed_in" },
    });
    expect(socket.messages).toHaveLength(3);
  });

  test("retains a compact final semantic state for benchmark verification", async () => {
    const bridge = new BrowserBridge();
    const socket = new MockSocket();
    bridge.attachNativeSocket(socket);
    bridge.handleNativeMessage(JSON.stringify({ type: "event", event: "extension.ready" }));
    const browser = new BrowserAutomation(bridge);

    const begin = browser.beginTask("run-final-state");
    await waitForMessages(socket, 1);
    respond(bridge, socket.messages[0], { isolated: true, windowId: 12 });
    await begin;

    const ending = browser.endTask("run-final-state");
    await waitForMessages(socket, 2);
    respond(bridge, socket.messages[1], {
      url: "https://example.com/form",
      title: "Form",
      text: "Submitted successfully. The secret is: dumbledore",
      elements: [{ ref: "success", role: "status", name: "Submitted successfully" }],
      delta: { changed: [] },
    });
    await waitForMessages(socket, 3);
    respond(bridge, socket.messages[2], { format: "jpeg", dataUrl: "data:image/jpeg;base64,aW1hZ2U=" });
    await waitForMessages(socket, 4);
    respond(bridge, socket.messages[3], { closed: true });
    await ending;

    expect(browser.getArtifacts("run-final-state")).toMatchObject({
      finalState: {
        url: "https://example.com/form",
        text: "Submitted successfully. The secret is: dumbledore",
        tree: expect.stringContaining("Submitted successfully"),
      },
      screenshots: ["aW1hZ2U="],
    });
  });
});

function respond(bridge: BrowserBridge, raw: string | undefined, result: unknown) {
  const envelope = JSON.parse(raw ?? "{}") as { id?: string };
  bridge.handleNativeMessage(JSON.stringify({ type: "result", id: envelope.id, ok: true, result }));
}

async function waitForMessages(socket: MockSocket, count: number) {
  const deadline = Date.now() + 1_000;
  while (socket.messages.length < count && Date.now() < deadline) await Bun.sleep(0);
  expect(socket.messages.length).toBeGreaterThanOrEqual(count);
}
