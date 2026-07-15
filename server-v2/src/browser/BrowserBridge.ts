type BrowserNativeSocket = {
  send(message: string): void;
};

export interface BrowserCommandEnvelope {
  command: string;
  payload?: Record<string, unknown>;
}

export interface BrowserBridgeStatus {
  extensionConnected: boolean;
  runtimeConnected: boolean;
  lastEvent?: string;
  lastError?: string;
  connectedAt?: number;
  lastSeenAt?: number;
}

interface PendingBrowserCommand {
  resolve(value: unknown): void;
  reject(error: Error): void;
  timeout: Timer;
}

export class BrowserBridge {
  private nativeSocket?: BrowserNativeSocket;
  private nativeSockets = new WeakSet<object>();
  private pending = new Map<string, PendingBrowserCommand>();
  private status: BrowserBridgeStatus = {
    extensionConnected: false,
    runtimeConnected: false,
  };

  attachNativeSocket(socket: BrowserNativeSocket) {
    this.nativeSocket = socket;
    this.nativeSockets.add(socket);
    this.status = {
      ...this.status,
      runtimeConnected: true,
      connectedAt: Date.now(),
      lastSeenAt: Date.now(),
      lastEvent: "native.connected",
      lastError: undefined,
    };
  }

  detachNativeSocket(socket: BrowserNativeSocket) {
    this.nativeSockets.delete(socket);
    if (this.nativeSocket !== socket) return;

    this.nativeSocket = undefined;

    this.status = {
      ...this.status,
      extensionConnected: false,
      runtimeConnected: false,
      lastSeenAt: Date.now(),
      lastEvent: "native.disconnected",
    };

    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("Chrome extension disconnected"));
      this.pending.delete(id);
    }
  }

  isNativeSocket(socket: object) {
    return this.nativeSockets.has(socket);
  }

  handleNativeMessage(raw: string) {
    let message: BrowserNativeMessage;

    try {
      message = JSON.parse(raw) as BrowserNativeMessage;
    } catch {
      this.status = {
        ...this.status,
        lastSeenAt: Date.now(),
        lastError: "Invalid browser bridge message",
      };
      return;
    }

    this.status = {
      ...this.status,
      lastSeenAt: Date.now(),
    };

    if (message.type === "event") {
      this.handleNativeEvent(message);
      return;
    }

    if (message.type !== "result" || !message.id) {
      return;
    }

    const pending = this.pending.get(message.id);
    if (!pending) return;

    clearTimeout(pending.timeout);
    this.pending.delete(message.id);

    if (message.ok) {
      pending.resolve(message.result);
    } else {
      pending.reject(new Error(message.error || "Browser command failed"));
    }
  }

  getStatus(): BrowserBridgeStatus {
    return { ...this.status };
  }

  async execute(envelope: BrowserCommandEnvelope, timeoutMs = Number(Bun.env.DETACH_BROWSER_COMMAND_TIMEOUT_MS || 25_000)) {
    if (!this.nativeSocket) {
      throw new Error("Chrome extension is not connected. Load the Detach Browser Agent extension and open its popup once.");
    }

    const command = envelope.command?.trim();
    if (!command) {
      throw new Error("Browser command is required");
    }

    const id = `browser_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;

    return await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Browser command timed out: ${command}`));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timeout });

      try {
        this.nativeSocket?.send(JSON.stringify({
          type: "command",
          id,
          command,
          payload: envelope.payload ?? {},
        }));
      } catch (error) {
        clearTimeout(timeout);
        this.pending.delete(id);
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  private handleNativeEvent(message: BrowserNativeEvent) {
    const event = message.event || "extension.event";
    let extensionConnected = this.status.extensionConnected;
    if (event === "extension.ready") extensionConnected = true;
    if (event === "extension.disconnected") extensionConnected = false;

    this.status = {
      ...this.status,
      extensionConnected,
      runtimeConnected: true,
      lastSeenAt: Date.now(),
      lastEvent: event,
      lastError: message.error,
    };

  }
}

type BrowserNativeMessage = BrowserNativeEvent | BrowserNativeResult;

interface BrowserNativeEvent {
  type: "event";
  event?: string;
  error?: string;
  payload?: unknown;
}

interface BrowserNativeResult {
  type: "result";
  id?: string;
  ok?: boolean;
  result?: unknown;
  error?: string;
}
