import type { ChatRequest } from "../protocol/messages";
import { findExecutable } from "../runtime/CapabilityDetector";
import { runProcess } from "../runtime/ProcessRunner";
import type { AgentAdapter, AgentRun, AgentStreamCallbacks } from "./AgentAdapter";
import { buildAgentPrompt, resolveWorkspace } from "./AgentPrompt";
import { asStringRecord, consumeJsonLines, createTempJsonFile, getString, summarizeShellCommand, withTimeout } from "./CliAdapterUtils";
import { buildClaudeAllowedTools, buildClaudeMCPConfig, enabledMCPServers } from "./MCPConfig";
import { isRetryableNetworkError } from "../activity/ActivityNormalizer";

export class ClaudeAdapter implements AgentAdapter {
  readonly id = "claude" as const;
  readonly displayName = "Claude";

  async isAvailable() {
    return Boolean(await findExecutable("claude"));
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun {
    let cancelled = false;
    let commandRun: ReturnType<typeof runProcess> | undefined;
    let heartbeat: Timer | undefined;
    let tempMCPConfig: ReturnType<typeof createTempJsonFile> | undefined;

    const finished = (async () => {
      const executable = await findExecutable("claude");
      if (!executable) {
        throw new Error("Claude Code was not found. Install Claude Code and sign in, then restart Detach.");
      }

      callbacks.onActivity("Starting Claude");

      const prompt = buildAgentPrompt(request);
      const cwd = resolveWorkspace(request.workspacePath);
      const args = buildClaudeArgs(prompt, request);
      const mcpServerCount = enabledMCPServers(request.mcpServers).length;

      if (mcpServerCount > 0) {
        tempMCPConfig = createTempJsonFile("detach-claude-mcp-", "mcp.json", buildClaudeMCPConfig(request.mcpServers));
        args.push("--mcp-config", tempMCPConfig.path);
        const allowedTools = buildClaudeAllowedTools(request.mcpServers);
        if (allowedTools.length > 0) {
          args.push("--allowedTools", ...allowedTools);
        }
        callbacks.onActivity(`Loaded ${mcpServerCount} MCP server${mcpServerCount === 1 ? "" : "s"} for Claude`);
      }

      let fullText = "";
      let stdoutBuffer = "";
      let stderrBuffer = "";
      let jsonLineBuffer = "";
      let lastAssistantSnapshot = "";
      let lastActivityAt = Date.now();

      commandRun = runProcess({
        command: executable,
        args,
        cwd,
        env: {
          NO_COLOR: "1",
          CLAUDE_CODE_SKIP_PROMPT_HISTORY: "1",
        },
        onStdout(chunk) {
          if (cancelled) return;
          stdoutBuffer += chunk;
          lastActivityAt = Date.now();
          const parsed = consumeJsonLines<ClaudeStreamEvent>((chunk), (event) => {
            handleClaudeEvent(event, callbacks, (text) => {
              if (!text) return;
              const delta = deltaFromSnapshot(lastAssistantSnapshot, text);
              lastAssistantSnapshot = text;
              if (!delta) return;
              fullText += delta;
              callbacks.onChunk(delta);
            });
          }, jsonLineBuffer);
          jsonLineBuffer = parsed.remainder;
        },
        onStderr(chunk) {
          stderrBuffer += chunk;
          lastActivityAt = Date.now();
          const status = summarizeClaudeStderr(chunk);
          if (status) callbacks.onActivity(status);
        },
      });

      callbacks.onActivity("Thinking…");

      heartbeat = setInterval(() => {
        if (cancelled) return;
        if (Date.now() - lastActivityAt >= 15_000) {
          callbacks.onActivity("Working…");
        }
      }, 15_000);

      const result = await withTimeout(commandRun.finished, resolveAgentTimeout(request.timeoutMs, Bun.env.DETACH_CLAUDE_TIMEOUT_MS), () => {
        cancelled = true;
        commandRun?.cancel();
      });

      if (jsonLineBuffer.trim()) {
        consumeJsonLines<ClaudeStreamEvent>("\n", (event) => {
          handleClaudeEvent(event, callbacks, (text) => {
            const delta = deltaFromSnapshot(lastAssistantSnapshot, text);
            lastAssistantSnapshot = text;
            if (!delta) return;
            fullText += delta;
            callbacks.onChunk(delta);
          });
        }, jsonLineBuffer);
      }

      if (cancelled) {
        return { text: fullText };
      }

      if (result.exitCode !== 0) {
        const detail = stderrBuffer.trim() || result.stderr.trim() || `Claude exited with code ${result.exitCode}`;
        throw new Error(detail);
      }

      return { text: fullText || extractClaudeFinalText(stdoutBuffer) || result.stdout.trim() };
    })();

    const cleanup = () => {
      if (heartbeat) clearInterval(heartbeat);
      tempMCPConfig?.cleanup();
    };
    finished.then(cleanup, cleanup);

    return {
      cancel() {
        cancelled = true;
        if (heartbeat) clearInterval(heartbeat);
        commandRun?.cancel();
        tempMCPConfig?.cleanup();
      },
      finished,
    };
  }
}

function resolveAgentTimeout(requested: number | undefined, agentOverride: string | undefined) {
  const value = Number(requested || agentOverride || Bun.env.DETACH_AGENT_TIMEOUT_MS || 900_000);
  return Number.isFinite(value) ? Math.max(30_000, Math.min(value, 3_600_000)) : 900_000;
}

export function buildClaudeArgs(prompt: string, request: ChatRequest) {
  const args = [
    "-p",
    prompt,
    "--output-format",
    "stream-json",
    "--verbose",
    "--include-partial-messages",
    "--no-session-persistence",
    "--permission-mode",
    Bun.env.DETACH_CLAUDE_PERMISSION_MODE?.trim() || "auto",
  ];

  if (request.model?.trim()) {
    args.push("--model", request.model.trim());
  }

  const reasoningEffort = request.modelSettings?.reasoningEffort?.trim();
  if (reasoningEffort && ["low", "medium", "high", "xhigh", "max"].includes(reasoningEffort)) {
    args.push("--effort", reasoningEffort);
  }

  return args;
}

type ClaudeStreamEvent = {
  type?: string;
  subtype?: string;
  result?: string;
  error?: string | { message?: string };
  message?: {
    content?: Array<{
      type?: string;
      text?: string;
      name?: string;
      input?: unknown;
    }>;
  };
  content?: unknown;
};

function handleClaudeEvent(event: ClaudeStreamEvent, callbacks: AgentStreamCallbacks, onText: (text: string) => void) {
  if (event.type === "system" && event.subtype === "init") {
    callbacks.onActivity("Claude session started");
    return;
  }

  if (event.type === "result") {
    if (event.result) onText(event.result);
    return;
  }

  if (event.type === "error") {
    callbacks.onActivity("Claude failed");
    return;
  }

  const content = event.message?.content;
  if (!Array.isArray(content)) return;

  const text = content.filter((item) => item.type === "text" && item.text).map((item) => item.text).join("");
  if (text) onText(text);

  const toolUse = content.find((item) => item.type === "tool_use" && item.name);
  if (toolUse?.name) {
    callbacks.onActivity(activityForToolUse(toolUse.name, toolUse.input), toolUse.name);
  }
}

function activityForToolUse(name: string, input: unknown) {
  if (name === "Bash") {
    const command = getString(asStringRecord(input)?.command);
    return summarizeShellCommand(command);
  }

  if (name === "Read") {
    const filePath = getString(asStringRecord(input)?.file_path);
    return filePath ? `Reading ${filePath.split("/").slice(-2).join("/")}` : "Reading a file";
  }

  if (name === "Grep") return "Searching files";
  if (name === "Glob") return "Finding files";
  if (name === "Edit" || name === "MultiEdit" || name === "Write") return "Editing files";

  return `Using ${name}`;
}

function summarizeClaudeStderr(chunk: string) {
  const line = chunk.trim().split(/\r?\n/).map((item) => item.trim()).filter(Boolean).at(-1);
  if (!line) return undefined;
  if (isRetryableNetworkError(line)) return "Retrying…";
  return undefined;
}

function deltaFromSnapshot(previous: string, next: string) {
  if (!next) return "";
  if (next.startsWith(previous)) return next.slice(previous.length);
  return next;
}

function extractClaudeFinalText(stdout: string) {
  let finalText = "";
  consumeJsonLines<ClaudeStreamEvent>(stdout.endsWith("\n") ? stdout : `${stdout}\n`, (event) => {
    if (event.type === "result" && event.result) {
      finalText = event.result;
      return;
    }

    const text = event.message?.content
      ?.filter((item) => item.type === "text" && item.text)
      .map((item) => item.text)
      .join("");
    if (text) finalText = text;
  });
  return finalText;
}
