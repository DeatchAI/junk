import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import { runProcess } from "../runtime/ProcessRunner";
import type { AgentAdapter, AgentStreamCallbacks } from "./AgentAdapter";
import { buildAgentPrompt, resolveWorkspace } from "./AgentPrompt";
import { consumeJsonLines, createTempJsonFile, withTimeout } from "./CliAdapterUtils";
import { buildClaudeMCPConfig, enabledMCPServers } from "./MCPConfig";
import { AmpStream } from "./amp/AmpStream";

export class AmpAdapter implements AgentAdapter {
  readonly id = "amp" as const;
  readonly displayName = "Amp";
  async isAvailable() { return Boolean(await findExecutable(this.id)); }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks) {
    let cancelled = false, child: ReturnType<typeof runProcess> | undefined;
    let config: ReturnType<typeof createTempJsonFile> | undefined;
    const finished = (async () => {
      const executable = await findExecutable(this.id);
      if (!executable) throw new Error("Amp was not found. Install Amp and run amp login, then restart Detach.");
      if (cancelled) throw new Error("Amp task cancelled.");
      if (enabledMCPServers(request.mcpServers).length) {
        config = createTempJsonFile("detach-amp-", "mcp.json", buildClaudeMCPConfig(request.mcpServers).mcpServers);
      }
      const stream = new AmpStream(callbacks);
      let remainder = "";
      callbacks.onActivity("Starting Amp");
      child = runProcess({
        command: executable, args: buildAmpArgs(request, config?.path),
        cwd: resolveWorkspace(request.workspacePath),
        env: { NO_COLOR: "1", AMP_REMOTE_CONTROL_TERMINAL: "0" },
        input: buildAgentPrompt(request),
        onStdout(chunk) {
          if (cancelled) return;
          remainder = consumeJsonLines(chunk, (event) => stream.handle(event), remainder).remainder;
        },
      });
      const timeout = Number(request.timeoutMs || Bun.env.DETACH_AMP_TIMEOUT_MS || Bun.env.DETACH_AGENT_TIMEOUT_MS || 900_000);
      const result = await withTimeout(child.finished,
        Number.isFinite(timeout) ? Math.max(30_000, Math.min(timeout, 3_600_000)) : 900_000,
        () => { cancelled = true; child?.cancel(); }, request.runId);
      if (cancelled) return { text: stream.text };
      if (remainder.trim()) consumeJsonLines("\n", (event) => stream.handle(event), remainder);
      if (stream.error) throw new Error(stream.error);
      if (result.exitCode !== 0) throw new Error(result.stderr.trim() || `Amp exited with code ${result.exitCode}`);
      if (!stream.resultSeen || !stream.text.trim()) throw new Error("Amp exited without a complete agent response.");
      return { text: stream.text };
    })();
    const cleanup = () => config?.cleanup();
    finished.then(cleanup, cleanup);
    return { cancel() { cancelled = true; child?.cancel(); }, finished };
  }
}

export function buildAmpArgs(request: ChatRequest, configPath?: string) {
  const args = [...(request.providerSessionId ? ["threads", "continue", request.providerSessionId] : []), "--execute", "--stream-json", "--no-color", "--no-ide"];
  if (configPath) args.push("--mcp-config", configPath);
  if (request.model?.trim()) args.push("--mode", request.model.trim());
  return args;
}
