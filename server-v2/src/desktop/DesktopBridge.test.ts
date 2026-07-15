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
