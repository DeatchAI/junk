type SecretAppSocket = { send(message: string): void };

export interface SecretCommandEnvelope {
  command: "secrets.search" | "secrets.use_browser";
  payload: Record<string, unknown>;
}

interface PendingSecretCommand {
  resolve(resultJson: string): void;
  reject(error: Error): void;
  timeout: Timer;
}

/**
 * Agent calls contain opaque IDs and metadata only. After local authentication,
 * a credential payload crosses this private app bridge once so the runtime can
 * bind it directly to verified extension DOM refs; it is never returned to the
 * agent, recorded in browser traces, or written to logs.
 */
export class SecretBridge {
  private appSocket?: SecretAppSocket;
  private pending = new Map<string, PendingSecretCommand>();

  attachAppSocket(socket: SecretAppSocket) { this.appSocket = socket; }

  detachAppSocket(socket: SecretAppSocket) {
    if (this.appSocket !== socket) return;
    this.appSocket = undefined;
    for (const [id, pending] of this.pending) {
      clearTimeout(pending.timeout);
      pending.reject(new Error("Detach macOS app disconnected"));
      this.pending.delete(id);
    }
  }

  handleResult(message: { id?: string; ok?: boolean; resultJson?: string; error?: string }) {
    if (!message.id) return;
    const pending = this.pending.get(message.id);
    if (!pending) return;
    clearTimeout(pending.timeout);
    this.pending.delete(message.id);
    if (message.ok) pending.resolve(message.resultJson ?? "null");
    else pending.reject(new Error(message.error || "Secret command failed"));
  }

  async execute(envelope: SecretCommandEnvelope, timeoutMs = 60_000) {
    if (!this.appSocket) throw new Error("Detach macOS app is not connected for secure credential use.");
    const id = `secret_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
    return await new Promise<string>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("Timed out waiting for Touch ID or secure credential entry."));
      }, timeoutMs);
      this.pending.set(id, { resolve, reject, timeout });
      try {
        this.appSocket?.send(JSON.stringify({ type: "secret_command", id, secretCommand: envelope.command, ...envelope.payload }));
      } catch (error) {
        clearTimeout(timeout);
        this.pending.delete(id);
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }
}
