import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { AgentAdapter, AgentStreamCallbacks } from "./AgentAdapter";
import { buildAgentPrompt, resolveWorkspace } from "./AgentPrompt";
import { asStringRecord, createTempTextFile, withTimeout } from "./CliAdapterUtils";
import { piRunExtension } from "./pi/PiExtension";
import { PiRPCProcess } from "./pi/PiRPCProcess";

export class PiAdapter implements AgentAdapter {
  readonly id = "pi" as const;
  readonly displayName = "Pi";
  async isAvailable() { return Boolean(await findExecutable(this.id)); }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks) {
    let cancelled = false, child: PiRPCProcess | undefined;
    let extension: ReturnType<typeof createTempTextFile> | undefined;
    const finished = (async () => {
      const executable = await findExecutable(this.id);
      if (!executable) throw new Error("Pi was not found. Install Pi, run pi and /login, then restart Detach.");
      if (cancelled) throw new Error("Pi task cancelled.");
      const marker = "detach-bridge-" + crypto.randomUUID();
      extension = createTempTextFile("detach-pi-", "detach.mjs", piRunExtension(request, marker));
      child = new PiRPCProcess({
        command: executable, args: buildPiArgs(request, extension.path),
        cwd: resolveWorkspace(request.workspacePath), callbacks,
      });
      return await withTimeout((async () => {
        const commands = asStringRecord(await child!.request("get_commands"));
        if (!Array.isArray(commands?.commands) || !commands.commands.some((command) => asStringRecord(command)?.name === marker)) {
          throw new Error("Pi could not load the Detach bridge. Update Pi to a version with built-in MCP support.");
        }
        callbacks.onActivity("Starting Pi");
        return await child!.run(buildAgentPrompt(request));
      })(), agentTimeout(request.timeoutMs), () => child?.cancel(), request.runId);
    })();
    const cleanup = () => { child?.dispose(); extension?.cleanup(); };
    finished.then(cleanup, cleanup);
    return { cancel() { cancelled = true; child?.cancel(); }, finished };
  }
}

export function buildPiArgs(request: ChatRequest, extensionPath: string) {
  const args = ["--mode", "rpc", "--extension", extensionPath];
  if (request.providerSessionId) args.push("--session", request.providerSessionPath || request.providerSessionId);
  if (request.model?.trim()) args.push("--model", request.model.trim());
  const effort = request.modelSettings?.reasoningEffort;
  if (effort) args.push("--thinking", effort);
  return args;
}

function agentTimeout(requested?: number) {
  const value = Number(requested || Bun.env.DETACH_PI_TIMEOUT_MS || Bun.env.DETACH_AGENT_TIMEOUT_MS || 900_000);
  return Number.isFinite(value) ? Math.max(30_000, Math.min(value, 3_600_000)) : 900_000;
}
