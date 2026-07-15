import type { AgentPermissionRequest, AgentStreamCallbacks } from "./AgentAdapter";
import {
  autoApprovedMCPToolIdentities,
  buildACPMCPServers,
  type ACPMCPServer,
} from "./MCPConfig";
import type { MCPServerConfig } from "../protocol/messages";

export interface ACPAgentProcessOptions {
  command: string;
  args: string[];
  cwd: string;
  env?: Record<string, string | undefined>;
  mcpServers?: MCPServerConfig[];
  callbacks: AgentStreamCallbacks;
}

export class ACPAgentProcess {
  private readonly process;
  private readonly encoder = new TextEncoder();
  private readonly decoder = new TextDecoder();
  private readonly pending = new Map<number, {
    resolve: (value: unknown) => void;
    reject: (error: Error) => void;
  }>();
  private readonly toolCalls = new Map<string, ACPToolCall>();
  private readonly autoApprovedIdentities: string[];
  private readonly callbacks: AgentStreamCallbacks;
  private nextId = 1;
  private stdoutBuffer = "";
  private stderrBuffer = "";
  private fullText = "";
  private sessionId?: string;
  private disposed = false;

  constructor(private readonly options: ACPAgentProcessOptions) {
    this.callbacks = options.callbacks;
    this.autoApprovedIdentities = autoApprovedMCPToolIdentities(options.mcpServers);
    this.process = Bun.spawn([options.command, ...options.args], {
      cwd: options.cwd,
      env: {
        ...Bun.env,
        ...withoutUndefined(options.env ?? {}),
      },
      stdin: "pipe",
      stdout: "pipe",
      stderr: "pipe",
    });

    void this.readStdout();
    void this.readStderr();
    void this.watchExit();
  }

  async run(prompt: string) {
    try {
      await this.request("initialize", {
        protocolVersion: 1,
        clientCapabilities: {
          fs: { readTextFile: false, writeTextFile: false },
          terminal: false,
        },
        clientInfo: {
          name: "detach",
          title: "Detach",
          version: "0.1.0",
        },
      });

      const session = asRecord(await this.request("session/new", {
        cwd: this.options.cwd,
        mcpServers: buildACPMCPServers(this.options.mcpServers),
      }));
      this.sessionId = getString(session?.sessionId);
      if (!this.sessionId) {
        throw new Error("ACP agent did not return a session ID.");
      }

      await this.request("session/prompt", {
        sessionId: this.sessionId,
        prompt: [{ type: "text", text: prompt }],
      });

      return { text: this.fullText };
    } finally {
      this.dispose();
    }
  }

  cancel() {
    if (this.sessionId && !this.disposed) {
      this.notify("session/cancel", { sessionId: this.sessionId });
    }
    this.dispose();
  }

  getStderr() {
    return this.stderrBuffer.trim();
  }

  private request(method: string, params: unknown) {
    const id = this.nextId++;
    const response = new Promise<unknown>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
    this.write({ jsonrpc: "2.0", id, method, params });
    return response;
  }

  private notify(method: string, params: unknown) {
    this.write({ jsonrpc: "2.0", method, params });
  }

  private write(message: unknown) {
    if (this.disposed || !this.process.stdin) return;
    this.process.stdin.write(this.encoder.encode(`${JSON.stringify(message)}\n`));
    this.process.stdin.flush();
  }

  private async readStdout() {
    const reader = this.process.stdout.getReader();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      this.stdoutBuffer += this.decoder.decode(value, { stream: true });
      this.consumeStdout();
    }
    this.stdoutBuffer += this.decoder.decode();
    this.consumeStdout(true);
  }

  private consumeStdout(flush = false) {
    const lines = this.stdoutBuffer.split(/\r?\n/);
    this.stdoutBuffer = flush ? "" : lines.pop() ?? "";

    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      try {
        void this.handleMessage(JSON.parse(trimmed) as ACPMessage);
      } catch {
        // ACP stdout should be JSON-RPC. Ignore incidental human-readable noise.
      }
    }

    if (flush && this.stdoutBuffer.trim()) {
      try {
        void this.handleMessage(JSON.parse(this.stdoutBuffer) as ACPMessage);
      } catch {
        // Ignore a trailing non-JSON line.
      }
      this.stdoutBuffer = "";
    }
  }

  private async readStderr() {
    const reader = this.process.stderr.getReader();
    const decoder = new TextDecoder();
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      this.stderrBuffer += decoder.decode(value, { stream: true });
    }
    this.stderrBuffer += decoder.decode();
  }

  private async watchExit() {
    const exitCode = await this.process.exited;
    if (this.disposed) return;
    const detail = this.stderrBuffer.trim() || `ACP agent exited with code ${exitCode}`;
    this.rejectPending(new Error(detail));
  }

  private async handleMessage(message: ACPMessage) {
    if (typeof message.id === "number" && !message.method) {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(new Error(message.error.message || "ACP request failed"));
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    if (message.method === "session/request_permission" && typeof message.id === "number") {
      await this.handlePermissionRequest(message.id, message.params);
      return;
    }

    if (message.method === "session/update" || message.method === "x.ai/session/update") {
      this.handleSessionUpdate(message.params);
    }
  }

  private handleSessionUpdate(value: unknown) {
    const params = asRecord(value);
    const update = asRecord(params?.update);
    const kind = getString(update?.sessionUpdate);

    if (kind === "agent_message_chunk") {
      const text = contentText(update?.content);
      if (!text) return;
      this.fullText += text;
      this.callbacks.onChunk(text);
      return;
    }

    if (kind === "tool_call") {
      const toolCallId = getString(update?.toolCallId);
      if (toolCallId) this.toolCalls.set(toolCallId, update as ACPToolCall);
      const title = getString(update?.title) || "Using a tool";
      this.callbacks.onActivity(title, toolIdentity(update ?? {}));
      return;
    }

    if (kind === "tool_call_update") {
      const toolCallId = getString(update?.toolCallId);
      if (toolCallId) {
        const prior = this.toolCalls.get(toolCallId) ?? {};
        this.toolCalls.set(toolCallId, { ...prior, ...update });
      }
    }
  }

  private async handlePermissionRequest(id: number, value: unknown) {
    const params = asRecord(value);
    const incoming = asRecord(params?.toolCall) ?? {};
    const toolCallId = getString(incoming.toolCallId);
    const toolCall = toolCallId
      ? { ...(this.toolCalls.get(toolCallId) ?? {}), ...incoming }
      : incoming;
    const options = Array.isArray(params?.options)
      ? params.options.flatMap((item) => {
          const record = asRecord(item);
          return record ? [record] : [];
        })
      : [];
    const isPreApproved = isAutoApprovedACPToolCall(toolCall, this.autoApprovedIdentities);
    let approved = isPreApproved;

    if (!approved && this.callbacks.onPermission) {
      approved = await this.callbacks.onPermission(permissionRequestFor(toolCall));
    }

    this.write({
      jsonrpc: "2.0",
      id,
      result: {
        outcome: selectACPPermissionOutcome(options, approved),
      },
    });
  }

  private dispose() {
    if (this.disposed) return;
    this.disposed = true;
    this.rejectPending(new Error("ACP agent stopped before completing the request."));
    try {
      this.process.stdin?.end();
    } catch {
      // The process may have already closed stdin.
    }
    this.process.kill();
  }

  private rejectPending(error: Error) {
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
  }
}

export function isAutoApprovedACPToolCall(toolCall: Record<string, unknown>, identities: string[]) {
  const candidates = identityCandidates(toolCall);
  return identities.some((identity) => {
    const expected = normalizeIdentity(identity);
    return candidates.some((candidate) => {
      const actual = normalizeIdentity(candidate);
      return actual === expected
        || actual.startsWith(`${expected}__`)
        || actual.includes(`mcp__${expected}__`)
        || actual.endsWith(`__${expected}`);
    });
  });
}

export function selectACPPermissionOutcome(
  options: Array<Record<string, unknown> | undefined>,
  approved: boolean
) {
  const preferredKinds = approved
    ? ["allow_once", "allow_always"]
    : ["reject_once", "reject_always"];

  for (const kind of preferredKinds) {
    const option = options.find((item) => getString(item?.kind) === kind);
    const optionId = getString(option?.optionId);
    if (optionId) return { outcome: "selected", optionId };
  }

  return { outcome: "cancelled" };
}

function permissionRequestFor(toolCall: Record<string, unknown>): AgentPermissionRequest {
  const title = getString(toolCall.title) || "Agent tool request";
  const rawInput = toolCall.rawInput;
  const description = rawInput === undefined
    ? title
    : `${title}\n\n${truncate(JSON.stringify(rawInput, null, 2), 4_000)}`;
  const kind = getString(toolCall.kind);

  return {
    title,
    description,
    riskLevel: kind === "delete" ? "dangerous" : kind === "read" || kind === "search" ? "safe" : "normal",
    toolName: toolIdentity(toolCall),
  };
}

function identityCandidates(toolCall: Record<string, unknown>) {
  const candidates = new Set<string>();
  const title = getString(toolCall.title);
  if (title) candidates.add(title);
  collectIdentityValues(toolCall.rawInput, candidates, 0);
  return [...candidates];
}

function collectIdentityValues(value: unknown, output: Set<string>, depth: number) {
  if (depth > 3) return;
  const record = asRecord(value);
  if (!record) return;

  for (const [key, item] of Object.entries(record)) {
    if (/^(name|tool|toolName|tool_name|server|serverName|server_name)$/i.test(key) && typeof item === "string") {
      output.add(item);
    }
    if (/^(tool|input|params|arguments)$/i.test(key)) {
      collectIdentityValues(item, output, depth + 1);
    }
  }
}

function toolIdentity(toolCall: Record<string, unknown>) {
  return identityCandidates(toolCall).find((item) => item !== getString(toolCall.title));
}

function normalizeIdentity(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9_]+/g, "_").replace(/^_|_$/g, "");
}

function contentText(value: unknown): string | undefined {
  if (typeof value === "string") return value;
  const record = asRecord(value);
  if (!record) return undefined;
  if (record.type === "text") return getString(record.text);
  const nested = asRecord(record.content);
  return nested?.type === "text" ? getString(nested.text) : undefined;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : undefined;
}

function getString(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function withoutUndefined(input: Record<string, string | undefined>) {
  return Object.fromEntries(Object.entries(input).filter(([, value]) => value !== undefined)) as Record<string, string>;
}

function truncate(value: string, maxLength: number) {
  return value.length <= maxLength ? value : `${value.slice(0, maxLength - 1)}…`;
}

interface ACPMessage {
  jsonrpc?: "2.0";
  id?: number;
  method?: string;
  params?: unknown;
  result?: unknown;
  error?: { code?: number; message?: string };
}

type ACPToolCall = Record<string, unknown>;
