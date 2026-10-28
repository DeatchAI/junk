import { ProviderToolActivity } from "../../activity/ProviderToolActivity";
import { processEnv } from "../../runtime/ProcessRunner";
import type { AgentStreamCallbacks } from "../AgentAdapter";
import { asStringRecord, getString } from "../CliAdapterUtils";
import { answerPiUI } from "./PiUI";

export interface PiRPCOptions {
  command: string;
  args: string[];
  cwd: string;
  callbacks: AgentStreamCallbacks;
  env?: Record<string, string>;
}

/** Strict LF-delimited RPC; command acceptance is not turn completion. */
export class PiRPCProcess {
  private readonly child;
  private readonly pending = new Map<string, { resolve(value: unknown): void; reject(error: Error): void }>();
  private readonly settled: Promise<void>;
  private settle!: () => void;
  private rejectRun!: (error: Error) => void;
  private buffer = "";
  private stderr = "";
  private fullText = "";
  private emittedMessageText = "";
  private disposed = false;
  private promptAccepted = false;
  private runEnded = false;
  private failure?: Error;
  private uiQueue: Promise<void> = Promise.resolve();

  constructor(private readonly options: PiRPCOptions) {
    this.settled = new Promise<void>((resolve, reject) => { this.settle = resolve; this.rejectRun = reject; });
    // A startup failure can precede run(); attach a rejection handler immediately.
    void this.settled.catch(() => {});
    this.child = Bun.spawn([options.command, ...options.args], {
      cwd: options.cwd, env: { ...processEnv(), ...options.env, NO_COLOR: "1" },
      stdin: "pipe", stdout: "pipe", stderr: "pipe",
    });
    void this.readStdout().catch((error) => this.fail(error));
    void new Response(this.child.stderr).text().then((text) => { this.stderr = text; });
    void this.child.exited.then((code) => {
      if (!this.disposed) this.fail(new Error(this.stderr || `Pi exited unexpectedly (${code})`));
    });
  }

  async request(type: string, payload: Record<string, unknown> = {}) {
    if (this.disposed) throw new Error("Pi has stopped.");
    if (this.failure) throw this.failure;
    const id = crypto.randomUUID();
    return new Promise<unknown>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      try { this.send({ type, id, ...payload }); }
      catch (error) { this.pending.delete(id); reject(error); }
    });
  }

  async run(message: string) {
    try {
      const state = asStringRecord(await this.request("get_state"));
      const sessionID = getString(state?.sessionId);
      if (sessionID) this.options.callbacks.onSession?.({ id: sessionID, path: getString(state?.sessionFile),
        title: getString(state?.sessionName), workspacePath: this.options.cwd, canResume: true });
      const result = asStringRecord(await this.request("prompt", { message }));
      this.promptAccepted = true;
      if (result?.disposition === "handled") {
        throw new Error("Pi handled this as a local command without running an agent turn.");
      }
      if (this.runEnded) this.settle();
      await this.settled;
      const saved = asStringRecord(await this.request("get_state"));
      if (getString(saved?.sessionId)) this.options.callbacks.onSession?.({ id: getString(saved?.sessionId)!,
        path: getString(saved?.sessionFile), title: getString(saved?.sessionName), workspacePath: this.options.cwd, canResume: true });
      if (!this.fullText.trim()) throw new Error("Pi completed without returning a response.");
      return { text: this.fullText };
    } finally { this.dispose(); }
  }

  cancel() {
    if (this.disposed) return;
    try { this.send({ type: "abort" }); } catch {}
    this.fail(new Error("Pi task cancelled."));
    this.dispose();
  }

  dispose() {
    if (this.disposed) return;
    this.disposed = true;
    try { this.child.stdin.end(); } catch {}
    this.child.kill();
    for (const request of this.pending.values()) request.reject(new Error("Pi has stopped."));
    this.pending.clear();
  }

  private send(value: unknown) {
    if (this.disposed) return;
    this.child.stdin.write(JSON.stringify(value) + "\n");
    this.child.stdin.flush();
  }

  private async readStdout() {
    const reader = this.child.stdout.getReader(), decoder = new TextDecoder();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      this.buffer += decoder.decode(value, { stream: true });
      if (this.buffer.length > 16 * 1024 * 1024) throw new Error("Pi emitted an oversized RPC frame.");
      let end: number;
      while ((end = this.buffer.indexOf("\n")) >= 0) {
        const line = this.buffer.slice(0, end).replace(/\r$/, "");
        this.buffer = this.buffer.slice(end + 1);
        if (line.trim()) this.handle(asStringRecord(JSON.parse(line)) ?? {});
      }
    }
  }

  private toolActivity?: ProviderToolActivity;

  private handle(frame: Record<string, unknown>) {
    const type = getString(frame.type);
    if (type === "response") {
      const id = getString(frame.id), request = id ? this.pending.get(id) : undefined;
      if (!request || !id) return;
      this.pending.delete(id);
      if (frame.success === false) request.reject(new Error(getString(frame.error) || "Pi command failed."));
      else request.resolve(frame.data);
    } else if (type === "extension_ui_request") {
      this.uiQueue = this.uiQueue.then(async () => {
        if (this.disposed) return;
        const response = await answerPiUI(frame, this.options.callbacks);
        if (response) this.send(response);
      }).catch((error) => this.fail(error));
    } else if (type === "message_start" && asStringRecord(frame.message)?.role === "assistant") {
      this.emittedMessageText = "";
    } else if (type === "message_update") {
      const event = asStringRecord(frame.assistantMessageEvent);
      if (event?.type === "text_delta") {
        const text = getString(event.delta) || "";
        this.emit(text); this.emittedMessageText += text;
      }
    } else if (type === "message_end") {
      const message = asStringRecord(frame.message);
      if (message?.role !== "assistant") return;
      if (["error", "aborted"].includes(String(message.stopReason))) {
        this.fail(new Error(getString(message.errorMessage) || "Pi could not finish this turn."));
        return;
      }
      const text = Array.isArray(message.content) ? message.content.map((part) => {
        const block = asStringRecord(part);
        return block?.type === "text" ? getString(block.text) || "" : "";
      }).join("") : "";
      if (text.startsWith(this.emittedMessageText)) this.emit(text.slice(this.emittedMessageText.length));
    } else if (type === "tool_execution_start") {
      this.toolActivity ??= new ProviderToolActivity("pi", this.options.callbacks);
      this.toolActivity.start(getString(frame.toolName) || "tool", frame.args, getString(frame.toolCallId));
    } else if (type === "tool_execution_end") {
      this.toolActivity ??= new ProviderToolActivity("pi", this.options.callbacks);
      const result = asStringRecord(frame.result);
      const output = Array.isArray(result?.content) ? result.content.map((part) => {
        const block = asStringRecord(part); return block?.type === "text" ? getString(block.text) || "" : "";
      }).join("\n") : "";
      this.toolActivity.finish(getString(frame.toolCallId), output, frame.isError === true, getString(frame.toolName));
    } else if (type === "agent_settled") {
      this.runEnded = true;
      if (frame.aborted === true) this.fail(new Error("Pi task cancelled."));
      else if (this.promptAccepted) this.settle();
    } else if (type === "extension_error") {
      this.fail(new Error(getString(frame.error) || getString(frame.message) || "Pi extension failed."));
    }
  }

  private emit(text: string) {
    if (!text || this.disposed) return;
    this.fullText += text;
    this.options.callbacks.onChunk(text);
  }

  private fail(error: unknown) {
    if (this.failure || this.disposed) return;
    this.failure = error instanceof Error ? error : new Error(String(error));
    for (const request of this.pending.values()) request.reject(this.failure);
    this.pending.clear();
    this.rejectRun(this.failure);
  }
}
