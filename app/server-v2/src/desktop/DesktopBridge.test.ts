import { describe, expect, test } from "bun:test";

import { DesktopBridge } from "./DesktopBridge";

class MockSocket {
  messages: string[] = [];

  send(message: string) {
    this.messages.push(message);
  }
}

describe("DesktopBridge", () => {
  test("routes a native result back to the pending desktop command", async () => {
    const bridge = new DesktopBridge();
    const socket = new MockSocket();
    bridge.attachAppSocket(socket);

    const command = bridge.execute({ command: "desktop.status" });
    const envelope = JSON.parse(socket.messages[0] ?? "{}") as { id?: string; type?: string };

    expect(envelope.type).toBe("desktop_command");
    expect(envelope.id).toBeString();

    bridge.handleResult({
      id: envelope.id,
      ok: true,
      result: { accessibilityGranted: true },
    });

    await expect(command).resolves.toEqual({ accessibilityGranted: true });
  });

  test("ignores an old app socket closing after a replacement connects", async () => {
    const bridge = new DesktopBridge();
    const first = new MockSocket();
    const second = new MockSocket();

    bridge.attachAppSocket(first);
    bridge.attachAppSocket(second);
    bridge.detachAppSocket(first);

    expect(bridge.getStatus().appConnected).toBe(true);
    const command = bridge.execute({ command: "desktop.list_apps" });
    const envelope = JSON.parse(second.messages[0] ?? "{}") as { id?: string };
    bridge.handleResult({ id: envelope.id, ok: true, result: { applications: [] } });

    await expect(command).resolves.toEqual({ applications: [] });
  });
});

test("desktop input requires a live run and cannot spoof internal session/deadline metadata", async () => {
  const bridge = new DesktopBridge(); const socket = new MockSocket(); bridge.attachAppSocket(socket);
  await expect(bridge.execute({ command: "desktop.click", runId: "missing" })).rejects.toThrow("active");
  bridge.registerRun("a");
  const pending = bridge.execute({ command: "desktop.observe", runId: "a", payload: { _sessionId: "b", _deadline: 0, pid: 42 } });
  const sent = JSON.parse(socket.messages[0]!);
  expect(sent.payload._sessionId).toBe("a"); expect(sent.payload._deadline).toBeGreaterThan(Date.now() / 1000);
  bridge.handleResult({ id: sent.id, ok: true, result: {} }); await pending;
  bridge.endRun("a");
  await expect(bridge.execute({ command: "desktop.click", runId: "a" })).rejects.toThrow("active");
});

test("stopping a desktop task rejects its pending work, clears native state and preserves another task", async () => {
  const bridge = new DesktopBridge(); const socket = new MockSocket(); bridge.attachAppSocket(socket);
  let cancelled = false;
  bridge.registerRun("a", () => { cancelled = true; }); bridge.registerRun("b");
  const pending = bridge.execute({ command: "desktop.observe", runId: "a" });
  const rejected = pending.catch((error: Error) => error.message);
  bridge.stopRun("a"); expect(await rejected).toContain("stopped"); expect(cancelled).toBe(true);
  expect(socket.messages.map((message) => JSON.parse(message)).some((message) => message.command === "desktop.end_session" && message.payload._sessionId === "a")).toBe(true);
  const other = bridge.execute({ command: "desktop.observe", runId: "b" });
  const last = JSON.parse(socket.messages.at(-1)!); bridge.handleResult({ id: last.id, ok: true, result: {} }); await other;
});

test("losing the desktop bridge stops desktop work without cancelling an unrelated coding task", async () => {
  const bridge = new DesktopBridge(); const socket = new MockSocket(); bridge.attachAppSocket(socket);
  let desktopCancelled = false, codingCancelled = false;
  bridge.registerRun("desktop", () => { desktopCancelled = true; });
  bridge.registerRun("coding", () => { codingCancelled = true; });
  const pending = bridge.execute({ command: "desktop.observe", runId: "desktop" }).catch((error: Error) => error.message);
  bridge.detachAppSocket(socket);
  expect(await pending).toContain("stopped");
  expect(desktopCancelled).toBe(true); expect(codingCancelled).toBe(false);
});

test("expired desktop work is revoked so a delayed native response cannot revive it", async () => {
  const bridge = new DesktopBridge(); const socket = new MockSocket(); bridge.attachAppSocket(socket);
  let cancelled = false; bridge.registerRun("a", () => { cancelled = true; });
  const pending = bridge.execute({ command: "desktop.observe", runId: "a" }, 5).catch((error: Error) => error.message);
  expect(await pending).toContain("timed out"); expect(cancelled).toBe(true);
  await expect(bridge.execute({ command: "desktop.observe", runId: "a" })).rejects.toThrow("active");
  const original = JSON.parse(socket.messages[0]!);
  bridge.handleResult({ id: original.id, ok: true, result: { revived: true } });
});
