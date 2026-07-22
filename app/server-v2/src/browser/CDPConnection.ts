export interface CDPEvent {
  method: string;
  params: Record<string, unknown>;
  sessionId?: string;
}

interface PendingCommand {
  method: string;
  resolve(value: Record<string, any>): void;
  reject(error: Error): void;
  timeout: Timer;
}

/** Minimal, dependency-free Chrome DevTools Protocol transport. */
export class CDPConnection {
  private nextId = 1;
  private pending = new Map<number, PendingCommand>();
  private listeners = new Set<(event: CDPEvent) => void>();
  private closed = false;

  private constructor(private readonly socket: WebSocket) {
    socket.addEventListener("message", (event) => this.handleMessage(String(event.data)));
    socket.addEventListener("close", () => this.handleClose("Power browser disconnected"));
    socket.addEventListener("error", () => this.handleClose("Power browser connection failed"));
  }

  static async connect(url: string, timeoutMs = 10_000) {
    const socket = new WebSocket(url);
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        socket.close();
        reject(new Error("Timed out connecting to the Power browser"));
      }, timeoutMs);

      socket.addEventListener("open", () => {
        clearTimeout(timeout);
        resolve();
      }, { once: true });
      socket.addEventListener("error", () => {
        clearTimeout(timeout);
        reject(new Error(`Could not connect to Chrome DevTools at ${url}`));
      }, { once: true });
    });
    return new CDPConnection(socket);
  }

  async send(
    method: string,
    params: Record<string, unknown> = {},
    sessionId?: string,
    timeoutMs = 25_000
  ): Promise<Record<string, any>> {
    if (this.closed || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("Power browser is not connected");
    }

    const id = this.nextId++;
    return await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP command timed out: ${method}`));
      }, timeoutMs);
      this.pending.set(id, { method, resolve, reject, timeout });
      this.socket.send(JSON.stringify({ id, method, params, sessionId }));
    });
  }

  onEvent(listener: (event: CDPEvent) => void) {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  close() {
    this.handleClose("Power browser connection closed");
    this.socket.close();
  }

  private handleMessage(raw: string) {
    let message: Record<string, any>;
    try {
      message = JSON.parse(raw) as Record<string, any>;
    } catch {
      return;
    }

    if (typeof message.id === "number") {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      clearTimeout(pending.timeout);
      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(new Error(`${pending.method}: ${message.error.message || `CDP command failed (${message.error.code ?? "unknown"})`}`));
      } else {
        pending.resolve(message.result ?? {});
      }
      return;
    }

    if (typeof message.method !== "string") return;
    const event: CDPEvent = {
      method: message.method,
      params: asRecord(message.params),
      sessionId: typeof message.sessionId === "string" ? message.sessionId : undefined,
    };
    for (const listener of this.listeners) listener(event);
  }

  private handleClose(message: string) {
    if (this.closed) return;
    this.closed = true;
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(new Error(message));
      this.pending.delete(id);
    }
  }
}

function asRecord(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}
