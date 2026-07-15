import { describe, expect, test } from "bun:test";

import { BrowserBridge } from "./BrowserBridge";

class MockSocket {
  messages: string[] = [];

  send(message: string) {
    this.messages.push(message);
  }
}

describe("BrowserBridge", () => {
  test("ignores a stale socket closing after a replacement connects", async () => {
    const bridge = new BrowserBridge();
    const first = new MockSocket();
    const second = new MockSocket();

    bridge.attachNativeSocket(first);
    bridge.attachNativeSocket(second);
    bridge.detachNativeSocket(first);

    expect(bridge.getStatus().runtimeConnected).toBe(true);

    const command = bridge.execute({ command: "browser.status" });
    const envelope = JSON.parse(second.messages[0] ?? "{}") as { id?: string };
    expect(envelope.id).toBeString();

    bridge.handleNativeMessage(JSON.stringify({
      type: "result",
      id: envelope.id,
      ok: true,
      result: { connected: true },
    }));

    await expect(command).resolves.toEqual({ connected: true });
  });

  test("marks the extension ready only after its handshake event", () => {
    const bridge = new BrowserBridge();
    const socket = new MockSocket();

    bridge.attachNativeSocket(socket);
    expect(bridge.getStatus().extensionConnected).toBe(false);

    bridge.handleNativeMessage(JSON.stringify({ type: "event", event: "extension.ready" }));
    expect(bridge.getStatus().extensionConnected).toBe(true);

    bridge.detachNativeSocket(socket);
    expect(bridge.getStatus()).toMatchObject({
      extensionConnected: false,
      runtimeConnected: false,
    });
  });
});
