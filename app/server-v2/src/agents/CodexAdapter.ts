import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import type { AgentAdapter, AgentRun, AgentStreamCallbacks } from "./AgentAdapter";
import { resolveWorkspace } from "./AgentPrompt";
import { shortPath, withTimeout } from "./CliAdapterUtils";
import { CodexAppServer } from "./codex/CodexAppServer";
import { imageAttachmentPaths } from "./codex/CodexConfiguration";
import { buildCodexPrompt } from "./codex/CodexPrompt";

export { codexActivityFromEvent } from "./codex/CodexActivity";
export { buildCodexAppServerArgs, buildCodexTurnParams } from "./codex/CodexConfiguration";
export { buildCodexMCPEnv } from "./codex/CodexMCPConfig";
export { buildCodexPrompt } from "./codex/CodexPrompt";

export class CodexAdapter implements AgentAdapter {
  readonly id = "codex" as const;
  readonly displayName = "Codex";

  constructor(private readonly executable = () => findExecutable("codex")) {}

  async isAvailable() {
    return Boolean(await this.executable());
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun {
    let cancelled = false;
    let server: CodexAppServer | undefined;
    let heartbeat: Timer | undefined;

    const finished = (async () => {
      const executable = await this.executable();
      if (cancelled) return { text: "" };
      if (!executable) {
        throw new Error("Codex CLI was not found. Install Codex and sign in, then restart Detach.");
      }
      callbacks.onActivity("Starting Codex");
      server = new CodexAppServer({
        executable,
        cwd: resolveWorkspace(request.workspacePath),
        request,
        callbacks: {
          ...callbacks,
          onChunk(text) { if (!cancelled) callbacks.onChunk(text); },
          onActivity(status, toolName, event) {
            if (!cancelled) callbacks.onActivity(status, toolName, event);
          },
          onPermission: callbacks.onPermission
            ? (permission) => cancelled ? Promise.resolve(false) : callbacks.onPermission!(permission)
            : undefined,
        },
      });
      const images = imageAttachmentPaths(request.files);
      if (images.length) {
        const title = images.length === 1 ? "Reading attached image" : `Reading ${images.length} attached images`;
        callbacks.onActivity(title, "image", {
          agent: "codex", kind: "attachment", phase: "started", title,
          subtitle: images.map(shortPath).slice(0, 3).join(", "),
          toolName: "image", userFacing: true, sourceEventType: "codex.input.image",
          details: { paths: images },
        });
      }
      heartbeat = setInterval(() => {
        if (!cancelled && server && !server.isAwaitingInput && Date.now() - server.lastActivityAt >= 15_000) {
          const title = server.isStartingTurn ? "Waiting for Codex to start replying" : "Working…";
          callbacks.onActivity(title, undefined, {
            agent: "codex", kind: "status", action: "generic", phase: "updated",
            title, userFacing: true,
          });
        }
      }, 15_000);
      try {
        return await withTimeout(server.run(buildCodexPrompt(request)), timeoutFor(request), () => server?.cancel(), request.runId);
      } catch (error) {
        if (cancelled) return { text: server.text };
        throw error;
      } finally {
        if (heartbeat) clearInterval(heartbeat);
      }
    })();

    return {
      cancel() {
        cancelled = true;
        if (heartbeat) clearInterval(heartbeat);
        server?.cancel();
      },
      finished,
    };
  }
}

function timeoutFor(request: ChatRequest) {
  const value = Number(request.timeoutMs || Bun.env.DETACH_CODEX_TIMEOUT_MS || Bun.env.DETACH_AGENT_TIMEOUT_MS || 900_000);
  return Number.isFinite(value) ? Math.max(30_000, Math.min(value, 3_600_000)) : 900_000;
}
