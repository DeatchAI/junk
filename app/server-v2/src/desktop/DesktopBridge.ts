type DesktopAppSocket = {
  send(message: string): void;
};

export interface DesktopCommandEnvelope {
  command: string;
  payload?: Record<string, unknown>;
}

export interface DesktopBridgeStatus {
  appConnected: boolean;
  connectedAt?: number;
  lastSeenAt?: number;
  lastCommand?: string;
  lastError?: string;
}

interface PendingDesktopCommand {
  resolve(value: unknown): void;
  reject(error: Error): void;
  timeout: Timer;
}

export class DesktopBridge {
  private appSocket?: DesktopAppSocket;
  private appSockets = new WeakSet<object>();
  private pending = new Map<string, PendingDesktopCommand>();
  private status: DesktopBridgeStatus = { appConnected: false };

  attachAppSocket(socket: DesktopAppSocket) {
    this.appSocket = socket;
    this.appSockets.add(socket);
    this.status = {
      ...this.status,
      appConnected: true,
      connectedAt: Date.now(),
      lastSeenAt: Date.now(),
      lastError: undefined,
    };
  }

  detachAppSocket(socket: DesktopAppSocket) {
    this.appSockets.delete(socket);
    if (this.appSocket !== socket) return;

    this.appSocket = undefined;
    this.status = {
      ...this.status,
      appConnected: false,
      lastSeenAt: Date.now(),
    };

    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("Detach macOS app disconnected"));
      this.pending.delete(id);
    }
  }

  isAppSocket(socket: object) {
    return this.appSockets.has(socket);
  }

  getStatus(): DesktopBridgeStatus {
    return { ...this.status };
  }

  handleResult(message: {
    id?: string;
    ok?: boolean;
    result?: unknown;
    error?: string;
  }) {
    if (!message.id) return;
    const pending = this.pending.get(message.id);
    if (!pending) return;

    clearTimeout(pending.timeout);
    this.pending.delete(message.id);
    this.status = {
      ...this.status,
      lastSeenAt: Date.now(),
      lastError: message.ok ? undefined : message.error || "macOS command failed",
    };

    if (message.ok) {
      pending.resolve(message.result);
    } else {
      pending.reject(new Error(message.error || "macOS command failed"));
    }
  }

  async execute(
    envelope: DesktopCommandEnvelope,
    timeoutMs = Number(Bun.env.DETACH_DESKTOP_COMMAND_TIMEOUT_MS || 30_000)
  ) {
    if (!this.appSocket) {
      throw new Error("Detach macOS app is not connected to the local runtime.");
    }

    const command = envelope.command?.trim();
    if (!command) throw new Error("macOS command is required");

    const id = `desktop_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
    this.status = {
      ...this.status,
      lastCommand: command,
      lastSeenAt: Date.now(),
      lastError: undefined,
    };

    return await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        this.status = {
          ...this.status,
          lastError: `macOS command timed out: ${command}`,
        };
        reject(new Error(`macOS command timed out: ${command}`));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timeout });

      try {
        this.appSocket?.send(JSON.stringify({
          type: "desktop_command",
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
}
