import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { processEnv, runProcess } from "../runtime/ProcessRunner";
import { withTimeout } from "../agents/CliAdapterUtils";
import { MAX_TRANSCRIPT_BYTES, record } from "./Transcript";

const readers = new Set<{ cancel(): void }>();
export function closeHistoryProcesses() { for (const reader of [...readers]) reader.cancel(); }

/** No prompts or tools: callers can only use the explicit history/export allowlist. */
export async function readHistoryCommand(executable: string, args: string[]) {
  if (!(args[0] === "session" && args[1] === "list") && !(args[0] === "export" && args.length === 2)
    && !(args[0] === "threads" && ["list", "export"].includes(args[1]!))) {
    throw new Error("Unsupported history command.");
  }
  const cwd = mkdtempSync(join(tmpdir(), "detach-import-"));
  let child: ReturnType<typeof runProcess> | undefined;
  let size = 0;
  try {
    child = runProcess({ command: executable, args, cwd, env: { NO_COLOR: "1", OPENCODE_DISABLE_AUTOUPDATE: "true" },
      onStdout(chunk) { size += Buffer.byteLength(chunk); if (size > MAX_TRANSCRIPT_BYTES) child?.cancel(); } });
    readers.add(child);
    const result = await withTimeout(child.finished, 30_000, () => child?.cancel());
    if (size > MAX_TRANSCRIPT_BYTES) throw new Error("The provider's history response is too large.");
    if (result.exitCode !== 0) throw new Error("The provider could not read its saved history. Check its installation and login.");
    return JSON.parse(result.stdout);
  } finally { if (child) { readers.delete(child); child.cancel(); } rmSync(cwd, { recursive: true, force: true }); }
}

export class ReadOnlyHistoryRPC {
  private readonly process;
  private readonly cwd = mkdtempSync(join(tmpdir(), "detach-import-codex-"));
  private nextId = 1;
  private buffer = "";
  private bytes = 0;
  private closed = false;
  private pending = new Map<number, { resolve: (value: any) => void; reject: (error: Error) => void }>();
  onSessionUpdate?: (params: any) => void;
  private readonly cancellation = { cancel: () => this.close() };
  constructor(executable: string, private readonly protocol: "codex" | "acp" = "codex", acpArgs = ["acp"]) {
    const args = protocol === "codex" ? ["app-server", "-c", "mcp_servers={}", "-c", 'approval_policy="never"', "-c", 'sandbox_mode="read-only"'] : acpArgs;
    try {
      this.process = Bun.spawn([executable, ...args],
        { cwd: this.cwd, env: { ...processEnv(), NO_COLOR: "1", OPENCODE_DISABLE_AUTOUPDATE: "true" }, stdin: "pipe", stdout: "pipe", stderr: "ignore" });
    } catch (error) { rmSync(this.cwd, { recursive: true, force: true }); throw error; }
    readers.add(this.cancellation);
    void this.read().catch(() => this.fail());
    void this.process.exited.then(() => this.fail());
  }
  async initialize() {
    const clientInfo = { name: "detach-history", version: "1.0.0" };
    const result = await this.request("initialize", this.protocol === "codex"
      ? { clientInfo, capabilities: { experimentalApi: true } }
      : { clientInfo, protocolVersion: 1, clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false } });
    if (this.protocol === "codex") this.process.stdin.write(JSON.stringify({ method: "initialized" }) + "\n");
    return result;
  }
  async request(method: string, params: unknown): Promise<any> {
    const allowed = this.protocol === "codex" ? ["initialize", "thread/list", "thread/read", "thread/turns/list", "thread/items/list", "account/rateLimits/read"] : ["initialize", "session/list", "session/load"];
    if (!allowed.includes(method)) throw new Error("Read-only history method required.");
    if (this.closed) throw new Error("Codex history connection closed.");
    const id = this.nextId++;
    const promise = new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
    try {
      this.process.stdin.write(JSON.stringify({ ...(this.protocol === "acp" ? { jsonrpc: "2.0" } : {}), id, method, params }) + "\n");
      return await withTimeout(promise, 15_000, () => this.close());
    }
    finally { this.pending.delete(id); }
  }
  close() {
    if (this.closed) return;
    this.closed = true;
    readers.delete(this.cancellation);
    this.process.kill();
    this.fail();
    rmSync(this.cwd, { recursive: true, force: true });
  }
  private fail() {
    for (const entry of this.pending.values()) entry.reject(new Error("Codex could not read saved history. Check your CLI version."));
    this.pending.clear();
  }
  private async read() {
    const decoder = new TextDecoder();
    for await (const chunk of this.process.stdout) {
      this.bytes += chunk.byteLength;
      if (this.bytes > MAX_TRANSCRIPT_BYTES * 2) { this.close(); return; }
      this.buffer += decoder.decode(chunk, { stream: true });
      if (Buffer.byteLength(this.buffer) > MAX_TRANSCRIPT_BYTES) { this.close(); return; }
      let newline: number;
      while ((newline = this.buffer.indexOf("\n")) !== -1) {
        const line = this.buffer.slice(0, newline); this.buffer = this.buffer.slice(newline + 1);
        let message: any; try { message = JSON.parse(line); } catch { continue; }
        if (!message) continue;
        if (this.protocol === "acp" && message.method && message.id !== undefined) {
          this.process.stdin.write(JSON.stringify({ jsonrpc: "2.0", id: message.id,
            ...(message.method === "session/request_permission" ? { result: { outcome: { outcome: "cancelled" } } }
              : { error: { code: -32601, message: "History reader cannot execute tools or access client files." } }) }) + "\n");
          continue;
        }
        if (message.method === "session/update") { this.onSessionUpdate?.(message.params); continue; }
        const pending = this.pending.get(message.id);
        if (!pending || message.method) continue;
        if (message.error) pending.reject(new Error(`Codex history method failed: ${String(record(message.error).message).slice(0, 150)}`));
        else pending.resolve(message.result);
        this.pending.delete(message.id);
      }
    }
  }
}

export class CodexHistoryRPC extends ReadOnlyHistoryRPC {}

export async function supportsACPSessionLoad(executable: string) {
  const rpc = new ReadOnlyHistoryRPC(executable, "acp");
  try { return record((await rpc.initialize()).agentCapabilities).loadSession === true; }
  catch { return false; }
  finally { rpc.close(); }
}
