const DEFAULT_RUNTIME_URL = "ws://127.0.0.1:3847/api/browser/native";

export async function runNativeBrowserHost() {
  const host = new NativeBrowserHost(resolveRuntimeUrl());
  await host.run();
}

class NativeBrowserHost {
  private runtime?: WebSocket;
  private extensionBuffer = Buffer.alloc(0);
  private runtimeQueue: unknown[] = [];
  private reconnectTimer?: Timer;
  private reconnectAttempt = 0;
  private isRunning = true;

  constructor(private readonly runtimeUrl: string) {}

  async run() {
    this.connectRuntime();
    await this.readExtensionMessages();
    this.isRunning = false;
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
    this.runtime?.close();
  }

  private connectRuntime() {
    if (!this.isRunning || this.runtime || this.reconnectTimer) return;

    const socket = new WebSocket(this.runtimeUrl);
    this.runtime = socket;

    socket.addEventListener("open", () => {
      if (this.runtime !== socket) return;
      this.reconnectAttempt = 0;
      this.writeExtensionMessage({ type: "event", event: "runtime.connected" });
      for (const message of this.runtimeQueue.splice(0)) {
        socket.send(JSON.stringify(message));
      }
    });

    socket.addEventListener("message", (event) => {
      if (this.runtime !== socket) return;
      const data = typeof event.data === "string" ? event.data : Buffer.from(event.data as ArrayBuffer).toString("utf8");
      try {
        this.writeExtensionMessage(JSON.parse(data));
      } catch {
        this.writeExtensionMessage({ type: "event", event: "runtime.error", error: "Invalid runtime message" });
      }
    });

    socket.addEventListener("close", () => {
      if (this.runtime !== socket) return;
      this.runtime = undefined;
      if (!this.isRunning) return;
      this.writeExtensionMessage({ type: "event", event: "runtime.disconnected" });
      this.scheduleReconnect();
    });

    socket.addEventListener("error", () => {
      if (this.runtime !== socket) return;
      this.writeExtensionMessage({ type: "event", event: "runtime.error", error: "Could not connect to Detach runtime" });
    });
  }

  private scheduleReconnect() {
    if (!this.isRunning || this.reconnectTimer) return;
    const delay = Math.min(1_000 * (2 ** this.reconnectAttempt), 15_000);
    this.reconnectAttempt += 1;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = undefined;
      this.connectRuntime();
    }, delay);
  }

  private async readExtensionMessages() {
    for await (const chunk of Bun.stdin.stream()) {
      this.extensionBuffer = Buffer.concat([this.extensionBuffer, Buffer.from(chunk)]);
      this.consumeExtensionBuffer();
    }
  }

  private consumeExtensionBuffer() {
    while (this.extensionBuffer.length >= 4) {
      const length = this.extensionBuffer.readUInt32LE(0);
      if (this.extensionBuffer.length < 4 + length) return;

      const body = this.extensionBuffer.subarray(4, 4 + length).toString("utf8");
      this.extensionBuffer = this.extensionBuffer.subarray(4 + length);

      try {
        this.sendRuntimeMessage(JSON.parse(body));
      } catch {
        this.writeExtensionMessage({ type: "event", event: "native.error", error: "Invalid extension message" });
      }
    }
  }

  private sendRuntimeMessage(message: unknown) {
    if (this.runtime?.readyState === WebSocket.OPEN) {
      this.runtime.send(JSON.stringify(message));
      return;
    }

    this.runtimeQueue.push(message);
    if (this.runtimeQueue.length > 50) {
      this.runtimeQueue.shift();
    }
  }

  private writeExtensionMessage(message: unknown) {
    const body = Buffer.from(JSON.stringify(message), "utf8");
    const header = Buffer.alloc(4);
    header.writeUInt32LE(body.length, 0);
    process.stdout.write(Buffer.concat([header, body]));
  }
}

function resolveRuntimeUrl() {
  const explicit = Bun.env.DETACH_BROWSER_RUNTIME_WS?.trim();
  if (explicit) return explicit;

  const port = Bun.env.DETACH_PORT?.trim() || Bun.env.PORT?.trim();
  if (port) return `ws://127.0.0.1:${port}/api/browser/native`;

  return DEFAULT_RUNTIME_URL;
}
