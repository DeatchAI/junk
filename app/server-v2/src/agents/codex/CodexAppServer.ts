import type { ChatRequest } from "../../protocol/messages";
import { processEnv } from "../../runtime/ProcessRunner";
import type { AgentStreamCallbacks } from "../AgentAdapter";
import { asStringRecord as record, consumeJsonLines, getString } from "../CliAdapterUtils";
import { codexApprovalResponse } from "./CodexApprovals";
import { buildCodexAppServerArgs, buildCodexThreadParams, buildCodexTurnParams } from "./CodexConfiguration";
import { buildCodexMCPEnv } from "./CodexMCPConfig";
import { CodexNotifications } from "./CodexNotifications";
import { parseAgentQuestions } from "../../questions/AgentQuestion";
import { isWaitingForAnswer } from "../../questions/QuestionWait";

interface ServerOptions {
  executable: string;
  cwd: string;
  request: ChatRequest;
  callbacks: AgentStreamCallbacks;
}

interface RPCMessage {
  id?: number | string;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: { message?: string };
}

export class CodexAppServer {
  private readonly process;
  private readonly events: CodexNotifications;
  private readonly pending = new Map<number, {
    resolve(value: unknown): void;
    reject(error: Error): void;
    timeout: Timer;
  }>();
  private readonly completion = Promise.withResolvers<void>();
  private approvalQueue: Promise<void> = Promise.resolve();
  private nextId = 1;
  private buffer = "";
  private stderr = "";
  private stopped = false;
  private settled = false;
  private threadId?: string;
  private turnId?: string;
  lastActivityAt = Date.now();

  constructor(private readonly options: ServerOptions) {
    this.events = new CodexNotifications(options.callbacks);
    // Initialization can fail before run() starts waiting on completion.
    void this.completion.promise.catch(() => undefined);
    this.process = Bun.spawn([options.executable, ...buildCodexAppServerArgs(options.request.mcpServers)], {
      cwd: options.cwd,
      env: { ...processEnv(), ...buildCodexMCPEnv(options.request.mcpServers) },
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });
    const stdout = this.readStdout();
    const stderr = this.readStderr();
    void Promise.all([this.process.exited, stdout, stderr]).then(([code]) => {
      if (!this.stopped && !this.settled) {
        this.fail(new Error(this.stderr.trim() || `Codex stopped before completing its response (exit ${code}).`));
      }
    }).catch((error) => this.fail(error));
  }

  get text() { return this.events.text; }

  async run(prompt: string) {
    try {
      await this.request("initialize", {
        clientInfo: { name: "detach", title: "Detach", version: "0.1.0" },
        capabilities: { experimentalApi: true },
      });
      this.write({ method: "initialized" });
      const binding = this.options.request.providerSessionId;
      const { ephemeral, serviceName, ...overrides } = buildCodexThreadParams(this.options.request, this.options.cwd);
      const fork = this.options.request.providerFork;
      const started = record(await this.request(fork?.kind === "codex" ? "thread/fork" : binding ? "thread/resume" : "thread/start", binding
        ? { ...overrides, threadId: binding, excludeTurns: true,
          ...(fork?.kind === "codex" ? { beforeTurnId: fork.beforeTurnId } : {}) }
        : buildCodexThreadParams(this.options.request, this.options.cwd)));
      this.threadId = getString(record(started?.thread)?.id);
      if (!this.threadId) throw new Error("Codex did not return a thread ID.");
      if (fork?.kind === "codex") {
        try {
          if (this.threadId === binding) throw new Error("Codex returned the original session instead of a branch.");
          const history = record(await this.request("thread/turns/list", {
            threadId: this.threadId, limit: 1, sortDirection: "desc", itemsView: "notLoaded",
          }));
          if (!Array.isArray(history?.data) || getString(record(history.data[0])?.id) !== fork.previousTurnId) {
            throw new Error("This Codex version could not fork at the requested message. Update Codex before editing past messages.");
          }
        } catch (error) {
          if (this.threadId !== binding) await this.request("thread/archive", { threadId: this.threadId }).catch(() => undefined);
          throw error;
        }
      }
      this.options.callbacks.onSession?.({ id: this.threadId, workspacePath: this.options.cwd,
        title: getString(record(started?.thread)?.name), canResume: true });

      const response = record(await this.request("turn/start", buildCodexTurnParams(
        this.options.request, this.options.cwd, this.threadId, prompt,
      )));
      this.turnId = getString(record(response?.turn)?.id) || this.turnId;
      await this.completion.promise;
      return { text: this.text };
    } finally {
      this.dispose();
    }
  }

  cancel() {
    if (this.threadId && this.turnId && !this.stopped) {
      this.write({ id: this.nextId++, method: "turn/interrupt", params: {
        threadId: this.threadId, turnId: this.turnId,
      } });
    }
    this.dispose();
  }

  private request(method: string, params: unknown) {
    if (this.stopped) return Promise.reject(new Error("Codex was stopped."));
    const id = this.nextId++;
    const response = new Promise<unknown>((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Codex timed out while starting ${method}.`));
      }, 30_000);
      this.pending.set(id, { resolve, reject, timeout });
    });
    this.write({ id, method, params });
    return response;
  }

  private write(message: unknown) {
    if (this.stopped) return;
    try {
      this.process.stdin.write(`${JSON.stringify(message)}\n`);
      this.process.stdin.flush();
    } catch (error) {
      this.fail(error instanceof Error ? error : new Error(String(error)));
    }
  }

  private async readStdout() {
    const decoder = new TextDecoder();
    const reader = this.process.stdout.getReader();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      this.consume(decoder.decode(value, { stream: true }));
    }
    this.consume(`${decoder.decode()}\n`);
  }

  private consume(chunk: string) {
    const parsed = consumeJsonLines<RPCMessage>(chunk, (message) => {
      this.lastActivityAt = Date.now();
      void this.handle(message).catch((error) => this.fail(error));
    }, this.buffer);
    this.buffer = parsed.remainder;
  }

  private async handle(message: RPCMessage) {
    if (this.stopped) return;
    if (message.id !== undefined && !message.method) {
      const pending = typeof message.id === "number" ? this.pending.get(message.id) : undefined;
      if (!pending) return;
      this.pending.delete(message.id as number);
      clearTimeout(pending.timeout);
      if (message.error) pending.reject(new Error(message.error.message || "Codex request failed."));
      else pending.resolve(message.result);
      return;
    }
    if (!message.method) return;
    const params = record(message.params) ?? {};
    if (message.id !== undefined) {
      if (params.threadId !== this.threadId || (this.turnId && params.turnId && params.turnId !== this.turnId)) {
        this.write({ id: message.id, error: { code: -32602, message: "Request does not belong to the active Codex turn." } });
        return;
      }
      // The native task surface displays one approval at a time. Queue before
      // invoking onPermission so a hidden request cannot start its UI timeout.
      this.approvalQueue = this.approvalQueue.then(async () => {
        if (this.stopped) return;
        const result = ["item/tool/requestUserInput", "tool/requestUserInput"].includes(message.method!)
          ? { answers: await this.options.callbacks.onQuestion?.(parseAgentQuestions(params)) ?? {} }
          : await codexApprovalResponse(
          message.method!, params, this.options.callbacks,
          this.events.items.get(getString(params.itemId) || ""),
        );
        if (result === undefined) {
          this.write({ id: message.id, error: { code: -32601, message: `Detach does not support ${message.method}.` } });
        } else {
          this.write({ id: message.id, result });
        }
      });
      await this.approvalQueue;
      return;
    }
    if (params.threadId !== this.threadId) return;
    if (message.method === "turn/started") {
      this.turnId = getString(record(params.turn)?.id);
    } else if (message.method === "turn/completed") {
      const turn = record(params.turn);
      if (this.turnId && turn?.id !== this.turnId) return;
      if (turn?.status === "completed") {
        this.settled = true;
        this.completion.resolve();
      } else {
        this.fail(new Error(getString(record(turn?.error)?.message) || `Codex turn ${turn?.status || "failed"}.`));
      }
    } else {
      this.events.handle(message.method, params);
    }
  }

  get isAwaitingInput() {
    return isWaitingForAnswer(this.options.request.runId);
  }

  private async readStderr() {
    const decoder = new TextDecoder();
    const reader = this.process.stderr.getReader();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      this.stderr = `${this.stderr}${decoder.decode(value, { stream: true })}`.slice(-8_000);
    }
    this.stderr += decoder.decode();
  }

  private fail(error: Error) {
    if (this.settled || this.stopped) return;
    this.settled = true;
    this.completion.reject(error);
    this.rejectPending(error);
  }

  private rejectPending(error: Error) {
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
    }
    this.pending.clear();
  }

  private dispose() {
    if (this.stopped) return;
    this.stopped = true;
    const error = new Error("Codex was stopped.");
    this.rejectPending(error);
    if (!this.settled) {
      this.settled = true;
      this.completion.reject(error);
    }
    try { this.process.stdin.end(); } catch { /* Process already closed. */ }
    this.process.kill();
  }
}
