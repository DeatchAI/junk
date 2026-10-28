import { validateDesktopCommand } from "./DesktopValidation";
type DesktopAppSocket = {
  send(message: string): void;
};

export interface DesktopCommandEnvelope {
  command: string;
  payload?: Record<string, unknown>;
  runId?: string;
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
  runId?: string;
}

export class DesktopBridge {
  private appSocket?: DesktopAppSocket;
  private appSockets = new WeakSet<object>();
  private pending = new Map<string, PendingDesktopCommand>();
  private sessions = new Map<string, () => void>();
  private usedRuns = new Set<string>();
  private status: DesktopBridgeStatus = { appConnected: false };

  registerRun(runId: string, cancel: () => void = () => undefined) {
    this.sessions.set(runId, cancel);
  }

  stopRun(runId: string) {
    const cancel = this.sessions.get(runId);
    this.endRun(runId);
    cancel?.();
  }

  endRun(runId: string) {
    if (!this.sessions.delete(runId)) return;
    this.usedRuns.delete(runId);
    for (const [id, pending] of this.pending) {
      if (pending.runId !== runId) continue;
      clearTimeout(pending.timeout);
      pending.reject(new Error("Desktop task stopped"));
      this.pending.delete(id);
    }
    this.appSocket?.send(JSON.stringify({ type: "desktop_command", id: `end_${crypto.randomUUID()}`,
      command: "desktop.end_session", payload: { _sessionId: runId } }));
  }

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

    for (const runId of [...this.usedRuns]) this.stopRun(runId);
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

    if (!["desktop.status", "desktop.list_apps"].includes(command) &&
      (!envelope.runId || !this.sessions.has(envelope.runId))) {
      throw new Error("An active Detach task is required for macOS tools.");
    }
    const safePayload = Object.fromEntries(Object.entries(envelope.payload ?? {}).filter(([key]) => !key.startsWith("_")));
    validateDesktopCommand(command, safePayload);
    if (envelope.runId && !["desktop.status", "desktop.list_apps"].includes(command)) this.usedRuns.add(envelope.runId);
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
        if (envelope.runId) this.stopRun(envelope.runId);
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timeout, runId: envelope.runId });

      try {
        this.appSocket?.send(JSON.stringify({
          type: "desktop_command",
          id,
          command,
          payload: { ...safePayload, _sessionId: envelope.runId, _deadline: Date.now() / 1000 + timeoutMs / 1000 },
        }));
      } catch (error) {
        clearTimeout(timeout);
        this.pending.delete(id);
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }
}
