import type { AgentActivityEvent, ChatRequest, MCPServerConfig } from "../protocol/messages";
import type { AgentAdapter, AgentRun, AgentStreamCallbacks } from "./AgentAdapter";
import { findExecutable } from "../runtime/CapabilityDetector";
import { runProcess } from "../runtime/ProcessRunner";
import { browserToolInstructions, capabilityToolInstructions, hasDetachBrowserTools, hasDetachCapabilityBroker, hasDetachMacOSTools, macOSToolInstructions } from "./AgentPrompt";
import { autoApprovedMCPServers } from "./MCPConfig";

export class CodexAdapter implements AgentAdapter {
  readonly id = "codex" as const;
  readonly displayName = "Codex";

  async isAvailable() {
    return Boolean(await findExecutable("codex"));
  }

  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun {
    let cancelled = false;
    let commandRun: ReturnType<typeof runProcess> | undefined;
    let heartbeat: Timer | undefined;

    const finished = (async () => {
      const executable = await findExecutable("codex");
      if (!executable) {
        throw new Error("Codex CLI was not found. Install Codex and sign in, then restart Detach.");
      }

      const prompt = buildCodexPrompt(request);
      const cwd = resolveWorkspace(request.workspacePath);
      const args = buildCodexExecArgs(
        prompt,
        request.model,
        request.mcpServers,
        request.files,
        request.modelSettings,
      );
      const env = buildCodexMCPEnv(request.mcpServers);
      const imageAttachments = imageAttachmentPaths(request.files);

      let fullText = "";
      let stderrBuffer = "";
      let stdoutBuffer = "";
      let jsonLineBuffer = "";
      let sawCodexEvent = false;
      let lastActivityAt = Date.now();
      let lastActivityKey = "";
      let lastActivitySentAt = 0;
      const activityCallbacks: AgentStreamCallbacks = {
        ...callbacks,
        onActivity(status, toolName, event) {
          if (!status?.trim()) return;
          const key = event?.id
            ? `${event.id}:${event.phase}:${status}`
            : `${toolName ?? "status"}:${status}`;
          const now = Date.now();
          if (key === lastActivityKey && now - lastActivitySentAt < 2_000) {
            return;
          }

          lastActivityKey = key;
          lastActivitySentAt = now;
          callbacks.onActivity(status, toolName, event);
        },
      };

      commandRun = runProcess({
        command: executable,
        args,
        cwd,
        env,
        input: prompt,
        onStdout(chunk) {
          if (cancelled) return;
          stdoutBuffer += chunk;
          lastActivityAt = Date.now();
          const parsed = consumeCodexJsonLines(chunk, (event) => {
            sawCodexEvent = true;
            handleCodexEvent(event, activityCallbacks, (text) => {
              fullText += text;
              callbacks.onChunk(text);
            });
          }, jsonLineBuffer);
          jsonLineBuffer = parsed.remainder;
        },
        onStderr(chunk) {
          stderrBuffer += chunk;
          lastActivityAt = Date.now();
          const status = summarizeCodexStatus(chunk);
          if (status) activityCallbacks.onActivity(status);
        },
      });

      if (imageAttachments.length > 0) {
        activityCallbacks.onActivity(
          imageAttachments.length === 1 ? "Reading attached image" : `Reading ${imageAttachments.length} attached images`,
          "image",
          {
            agent: "codex",
            kind: "attachment",
            phase: "started",
            title: imageAttachments.length === 1 ? "Reading attached image" : `Reading ${imageAttachments.length} attached images`,
            subtitle: imageAttachments.map(shortPath).slice(0, 3).join(", "),
            toolName: "image",
            userFacing: true,
            sourceEventType: "codex.input.image",
            details: { paths: imageAttachments },
          }
        );
      }

      heartbeat = setInterval(() => {
        if (cancelled) return;
        if (Date.now() - lastActivityAt >= 15_000) {
          activityCallbacks.onActivity("Working…", undefined, {
            agent: "codex",
            kind: "status",
            action: "generic",
            phase: "updated",
            title: "Working…",
            userFacing: true,
          });
        }
      }, 15_000);

      const timeoutMs = resolveAgentTimeout(request.timeoutMs, Bun.env.DETACH_CODEX_TIMEOUT_MS);
      const result = await withTimeout(commandRun.finished, timeoutMs, () => {
        cancelled = true;
        commandRun?.cancel();
      });

      if (jsonLineBuffer.trim()) {
        consumeCodexJsonLines("\n", (event) => {
          sawCodexEvent = true;
          handleCodexEvent(event, activityCallbacks, (text) => {
            fullText += text;
            callbacks.onChunk(text);
          });
        }, jsonLineBuffer);
      }

      if (cancelled) {
        return { text: fullText };
      }

      if (result.exitCode !== 0) {
        const detail = stderrBuffer.trim() || result.stderr.trim() || `Codex exited with code ${result.exitCode}`;
        throw new Error(detail);
      }

      return { text: fullText || extractFinalTextFromJsonl(stdoutBuffer) || (sawCodexEvent ? "" : result.stdout) };
    })();

    const cleanup = () => {
      if (heartbeat) clearInterval(heartbeat);
    };
    finished.then(cleanup, cleanup);

    return {
      cancel() {
        cancelled = true;
        if (heartbeat) clearInterval(heartbeat);
        commandRun?.cancel();
      },
      finished,
    };
  }
}

function summarizeCodexStatus(chunk: string) {
  const lines = chunk.trim().split("\n").map((line) => line.trim()).filter(Boolean);
  const last = lines.at(-1);
  if (!last) return undefined;

  if (isInternalCodexDiagnostic(last)) {
    return undefined;
  }

  if (last === "Reading additional input from stdin...") {
    return "Sending prompt to Codex";
  }

  return undefined;
}

function isInternalCodexDiagnostic(line: string) {
  const noisyPatterns = [
    "rmcp::transport",
    "Transport channel closed",
    "codex_state::runtime",
    "codex_rollout::state_db",
    "failed to open state db",
    "failed to initialize state runtime",
    "hook:",
    "Stop Failed",
    "WARNING: proceeding",
    "PATH aliases",
    "ERROR ",
  ];

  return noisyPatterns.some((pattern) => line.includes(pattern));
}

export function buildCodexExecArgs(
  _prompt: string,
  model?: string,
  mcpServers: MCPServerConfig[] = [],
  files: Array<{ path: string; mimeType?: string }> = [],
  modelSettings?: ChatRequest["modelSettings"]
) {
  const args = ["exec", "--json", "--skip-git-repo-check", "--ephemeral", "--color", "never"];

  if (model?.trim()) {
    args.push("--model", model.trim());
  }

  const reasoningEffort = modelSettings?.reasoningEffort?.trim();
  if (reasoningEffort && ["low", "medium", "high", "xhigh", "max", "ultra"].includes(reasoningEffort)) {
    args.push("-c", `model_reasoning_effort=${tomlString(reasoningEffort)}`);
  }

  for (const path of imageAttachmentPaths(files)) {
    args.push("--image", path);
  }

  for (const server of mcpServers.filter((item) => item.enabled)) {
    args.push(...codexMCPConfigArgs(server));
  }

  args.push("-");
  return args;
}

function imageAttachmentPaths(files: Array<{ path: string; mimeType?: string }> = []) {
  return files
    .filter((file) => file.path?.trim() && isImageAttachment(file))
    .map((file) => file.path.trim());
}

function isImageAttachment(file: { path: string; mimeType?: string }) {
  if (file.mimeType?.toLowerCase().startsWith("image/")) return true;
  return /\.(png|jpe?g|gif|webp|heic|heif|tiff?|bmp)$/i.test(file.path);
}

function codexMCPConfigArgs(server: MCPServerConfig) {
  const key = sanitizeMCPKey(server.id || server.name);
  const args: string[] = [];

  if ((server.transport === "http" || server.transport === "sse") && server.url?.trim()) {
    args.push("-c", `mcp_servers.${key}.url=${tomlString(server.url.trim())}`);
  }

  if (server.transport === "stdio" && server.command?.trim()) {
    args.push("-c", `mcp_servers.${key}.command=${tomlString(server.command.trim())}`);
    if (server.args?.length) {
      args.push("-c", `mcp_servers.${key}.args=${tomlStringArray(server.args)}`);
    }
    for (const [envKey, envValue] of Object.entries(server.env ?? {})) {
      if (!isSafeConfigKey(envKey)) continue;
      args.push("-c", `mcp_servers.${key}.env.${envKey}=${tomlString(envValue)}`);
    }
  }

  const envHttpHeaders = tomlInlineStringMap(codexHTTPHeaderEnvMap(key, server.headers));
  if (envHttpHeaders) {
    args.push("-c", `mcp_servers.${key}.env_http_headers=${envHttpHeaders}`);
  }

  if (autoApprovedMCPServers([server]).length > 0) {
    // `codex exec` is non-interactive, so its default MCP approval prompt cannot
    // be answered by Detach and is reported as "user cancelled MCP tool call".
    // Trust only servers explicitly marked by Detach's shared tool policy;
    // user-configured MCP servers retain Codex's normal approval behavior.
    args.push("-c", `mcp_servers.${key}.default_tools_approval_mode=${tomlString("approve")}`);
  }

  return args;
}

export function buildCodexMCPEnv(mcpServers: MCPServerConfig[] = []) {
  const env: Record<string, string> = {};

  for (const server of mcpServers.filter((item) => item.enabled)) {
    if (server.transport !== "http" && server.transport !== "sse") continue;
    const key = sanitizeMCPKey(server.id || server.name);

    for (const [headerName, value] of Object.entries(server.headers ?? {})) {
      if (!headerName.trim() || !value.trim()) continue;
      env[codexHTTPHeaderEnvVarName(key, headerName)] = value;
    }
  }

  return env;
}

function codexHTTPHeaderEnvMap(serverKey: string, headers?: Record<string, string>) {
  const entries = Object.entries(headers ?? {}).filter(([headerName, value]) => headerName.trim() && value.trim());
  if (entries.length === 0) return undefined;

  return Object.fromEntries(
    entries.map(([headerName]) => [headerName, codexHTTPHeaderEnvVarName(serverKey, headerName)])
  );
}

function codexHTTPHeaderEnvVarName(serverKey: string, headerName: string) {
  const normalizedServer = serverKey.toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/^_|_$/g, "");
  const normalizedHeader = headerName.toUpperCase().replace(/[^A-Z0-9]+/g, "_").replace(/^_|_$/g, "");
  return `DETACH_MCP_${normalizedServer || "SERVER"}_${normalizedHeader || "HEADER"}`;
}

function sanitizeMCPKey(value: string) {
  const sanitized = value.toLowerCase().replace(/[^a-z0-9_]/g, "_").replace(/_+/g, "_").replace(/^_|_$/g, "");
  return sanitized || `mcp_${Date.now().toString(36)}`;
}

function isSafeConfigKey(value: string) {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(value);
}

function tomlString(value: string) {
  return JSON.stringify(value);
}

function tomlStringArray(values: string[]) {
  return `[${values.map(tomlString).join(", ")}]`;
}

function tomlInlineStringMap(values?: Record<string, string>) {
  const entries = Object.entries(values ?? {}).filter(
    ([key, value]) => key.trim() && typeof value === "string" && value.trim()
  );

  if (entries.length === 0) return undefined;

  return `{${entries.map(([key, value]) => `${tomlString(key)}=${tomlString(value)}`).join(", ")}}`;
}

function consumeCodexJsonLines(
  chunk: string,
  onEvent: (event: CodexExecEvent) => void,
  previousRemainder = ""
) {
  const combined = `${previousRemainder}${chunk}`;
  const lines = combined.split(/\r?\n/);
  const remainder = lines.pop() ?? "";

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      onEvent(JSON.parse(trimmed) as CodexExecEvent);
    } catch {
      // Keep malformed/non-JSON stdout out of the user-facing stream.
    }
  }

  return { remainder };
}

type CodexExecEvent = {
  type?: string;
  item?: {
    id?: string;
    type?: string;
    text?: string;
    command?: string;
    aggregated_output?: string;
    exit_code?: number | null;
    status?: string;
    changes?: Array<{
      path?: string;
      kind?: string;
    }>;
    server?: string;
    tool?: string;
    arguments?: unknown;
    result?: unknown;
    error?: unknown;
    items?: Array<{
      text?: string;
      completed?: boolean;
    }>;
    message?: string;
  };
  message?: string;
  error?: string | { message?: string };
  usage?: unknown;
};

function handleCodexEvent(
  event: CodexExecEvent,
  callbacks: AgentStreamCallbacks,
  onText: (text: string) => void
) {
  const activity = codexActivityFromEvent(event);
  if (activity && shouldForwardCodexActivity(activity)) {
    callbacks.onActivity(activity.title, activity.toolName, activity);
  }

  if (event.item?.type === "agent_message" && event.item.text) {
    onText(event.item.text);
    return;
  }

}

export function codexActivityFromEvent(event: CodexExecEvent): AgentActivityEvent | undefined {
  switch (event.type) {
    case "thread.started":
      return codexEvent({
        kind: "lifecycle",
        phase: "started",
        title: "Codex thread started",
        userFacing: false,
        sourceEventType: event.type,
      });
    case "turn.started":
      return codexEvent({
        kind: "lifecycle",
        phase: "started",
        title: "Codex turn started",
        userFacing: false,
        sourceEventType: event.type,
      });
    case "turn.completed":
      return codexEvent({
        kind: "lifecycle",
        phase: "completed",
        title: "Codex turn completed",
        userFacing: false,
        sourceEventType: event.type,
      });
    case "turn.failed":
      return codexEvent({
        kind: "error",
        phase: "failed",
        title: "Codex failed",
        subtitle: codexErrorMessage(event.error),
        userFacing: true,
        sourceEventType: event.type,
      });
    case "error":
      return codexEvent({
        kind: "error",
        phase: "failed",
        title: "Codex error",
        subtitle: codexErrorMessage(event.error ?? event.message),
        userFacing: false,
        sourceEventType: event.type,
      });
  }

  const item = event.item;
  if (!item?.type) return undefined;
  const phase = codexItemPhase(event);
  const base = {
    id: item.id,
    phase,
    sourceEventType: event.type,
    sourceItemType: item.type,
  } satisfies Partial<AgentActivityEvent>;

  switch (item.type) {
    case "agent_message":
      return undefined;
    case "command_execution":
      return codexEvent({
        ...base,
        kind: "command",
        title: summarizeCommand(item.command),
        subtitle: commandSubtitle(item),
        toolName: "terminal",
        userFacing: true,
        details: {
          exitCode: item.exit_code ?? undefined,
          status: item.status,
        },
      });
    case "file_change":
      return codexEvent({
        ...base,
        kind: "file_change",
        title: summarizeFileChange(item.changes),
        subtitle: summarizeFileChangeSubtitle(item.changes),
        toolName: "file",
        userFacing: true,
        details: {
          status: item.status,
          changes: item.changes,
        },
      });
    case "mcp_tool_call":
      return codexEvent({
        ...base,
        kind: "mcp_tool",
        title: summarizeMCPToolCall(item.server, item.tool),
        subtitle: item.server,
        toolName: item.tool ?? item.server ?? "mcp",
        userFacing: true,
        details: {
          server: item.server,
          tool: item.tool,
          status: item.status,
          arguments: sanitizeActivityValue(item.arguments),
          result: sanitizeActivityValue(item.result),
          error: sanitizeActivityValue(item.error),
        },
      });
    case "todo_list":
      return codexEvent({
        ...base,
        kind: "plan",
        title: summarizeTodoList(item.items),
        toolName: "plan",
        userFacing: false,
        details: {
          items: item.items,
        },
      });
    case "error":
      return codexEvent({
        ...base,
        kind: "error",
        phase: "failed",
        title: "Codex reported an error",
        subtitle: item.message,
        userFacing: true,
      });
    default:
      return codexEvent({
        ...base,
        kind: "status",
        title: humanizeIdentifier(item.type),
        userFacing: false,
      });
  }
}

function codexEvent(event: Omit<AgentActivityEvent, "agent">): AgentActivityEvent {
  return { agent: "codex", ...event };
}

function shouldForwardCodexActivity(event: AgentActivityEvent) {
  if (!event.userFacing) return false;
  return true;
}

function codexItemPhase(event: CodexExecEvent): AgentActivityEvent["phase"] {
  const status = event.item?.status;
  if (status === "failed") return "failed";
  if (status === "completed") return "completed";
  if (status === "in_progress") return "started";
  if (event.type === "item.started") return "started";
  if (event.type === "item.completed") return "completed";
  return "updated";
}

function summarizeCommand(command?: string) {
  if (!command?.trim()) return "Running a command";

  const cleaned = command.trim().replace(/\s+/g, " ");
  const searchMatch = cleaned.match(/\brg\b.*?["']([^"']{3,80})["']/);
  if (searchMatch?.[1]) return `Searching for "${searchMatch[1]}"`;

  const sedMatch = cleaned.match(/\bsed\s+-n\s+['"]?([^'"]+)['"]?\s+(.+)$/);
  if (sedMatch?.[1]) return `Reading ${shortPath(sedMatch[2] ?? "file")} (${sedMatch[1]})`;

  if (cleaned.includes("git status")) return "Checking repository status";
  if (cleaned.includes("git diff")) return "Reviewing local changes";
  if (cleaned.includes("ls ")) return "Listing files";

  return `Running ${cleaned.length > 90 ? `${cleaned.slice(0, 87)}...` : cleaned}`;
}

function commandSubtitle(item: NonNullable<CodexExecEvent["item"]>) {
  if (item.status === "failed" && typeof item.exit_code === "number") {
    return `Exited with code ${item.exit_code}`;
  }

  return undefined;
}

function summarizeFileChange(changes?: Array<{ path?: string; kind?: string }>) {
  const visible = changes?.filter((change) => change.path?.trim()) ?? [];
  if (visible.length === 0) return "Updating files";
  if (visible.length > 1) return `Updating ${visible.length} files`;

  const change = visible[0];
  if (!change) return "Updating files";
  const path = shortPath(change.path ?? "file");
  switch (change.kind) {
    case "add":
      return `Creating ${path}`;
    case "delete":
      return `Deleting ${path}`;
    case "update":
      return `Editing ${path}`;
    default:
      return `Updating ${path}`;
  }
}

function summarizeFileChangeSubtitle(changes?: Array<{ path?: string; kind?: string }>) {
  const visible = changes?.filter((change) => change.path?.trim()) ?? [];
  if (visible.length <= 1) return undefined;
  return visible.map((change) => shortPath(change.path ?? "file")).slice(0, 3).join(", ");
}

function summarizeMCPToolCall(server?: string, tool?: string) {
  const name = tool ?? server ?? "MCP tool";
  const normalized = name.replace(/^mcp__[^_]+__/, "");

  const labels: Record<string, string> = {
    detach_browser_execute: "Running browser program",
    detach_browser_status: "Checking browser status",
    detach_browser_list_tabs: "Listing browser tabs",
    detach_browser_open_tab: "Opening browser tab",
    detach_browser_activate_tab: "Activating browser tab",
    detach_browser_close_tab: "Closing browser tab",
    detach_browser_navigate: "Navigating browser",
    detach_browser_back: "Going back in browser",
    detach_browser_forward: "Going forward in browser",
    detach_browser_refresh: "Refreshing browser page",
    detach_browser_snapshot: "Inspecting browser page",
    detach_browser_extract_text: "Reading browser page",
    detach_browser_click: "Clicking in browser",
    detach_browser_hover: "Hovering in browser",
    detach_browser_type: "Typing in browser",
    detach_browser_key: "Pressing browser keys",
    detach_browser_dropdown_options: "Reading dropdown options",
    detach_browser_select: "Selecting browser option",
    detach_browser_upload_file: "Uploading browser file",
    detach_browser_scroll: "Scrolling browser page",
    detach_browser_wait: "Waiting for browser condition",
    detach_browser_screenshot: "Capturing browser screenshot",
    detach_macos_status: "Checking macOS permissions",
    detach_macos_snapshot: "Inspecting macOS screen",
    detach_macos_screenshot: "Capturing macOS screenshot",
    detach_macos_click: "Clicking in macOS app",
    detach_macos_type: "Typing in macOS app",
    detach_macos_key: "Pressing macOS keys",
  };

  return labels[normalized] ?? `Using ${humanizeIdentifier(normalized)}`;
}

function summarizeTodoList(items?: Array<{ text?: string; completed?: boolean }>) {
  const visible = items?.filter((item) => item.text?.trim()) ?? [];
  if (visible.length === 0) return "Updating plan";
  const incomplete = visible.filter((item) => !item.completed);
  const next = incomplete[0] ?? visible.at(-1);
  return next?.text ? `Planning: ${next.text}` : "Updating plan";
}

function codexErrorMessage(error: CodexExecEvent["error"] | string | undefined) {
  if (!error) return undefined;
  if (typeof error === "string") {
    return parseNestedErrorMessage(error);
  }
  return parseNestedErrorMessage(error.message ?? "");
}

function sanitizeActivityValue(value: unknown): unknown {
  if (value === undefined || value === null) return value;
  if (typeof value === "string") return value.length <= 2_000 ? value : `${value.slice(0, 2_000)}...`;
  try {
    const serialized = JSON.stringify(value);
    return serialized.length <= 4_000 ? value : `${serialized.slice(0, 4_000)}...`;
  } catch {
    return String(value);
  }
}

function parseNestedErrorMessage(message: string) {
  const trimmed = message.trim();
  if (!trimmed) return undefined;

  try {
    const parsed = JSON.parse(trimmed) as { error?: { message?: string }; message?: string };
    return parsed.error?.message ?? parsed.message ?? trimmed;
  } catch {
    return trimmed;
  }
}

function resolveAgentTimeout(requested: number | undefined, agentOverride: string | undefined) {
  const value = Number(requested || agentOverride || Bun.env.DETACH_AGENT_TIMEOUT_MS || 900_000);
  return Number.isFinite(value) ? Math.max(30_000, Math.min(value, 3_600_000)) : 900_000;
}

function humanizeIdentifier(value: string) {
  return value
    .replace(/^detach_/, "")
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function shortPath(path: string) {
  const trimmed = path.trim().replace(/^["']|["']$/g, "");
  const parts = trimmed.split("/");
  return parts.slice(-2).join("/") || trimmed;
}

function extractFinalTextFromJsonl(stdout: string) {
  let finalText = "";
  consumeCodexJsonLines(stdout.endsWith("\n") ? stdout : `${stdout}\n`, (event) => {
    if (event.item?.type === "agent_message" && event.item.text) {
      finalText = event.item.text;
    }
  });
  return finalText;
}

async function withTimeout<T>(promise: Promise<T>, timeoutMs: number, onTimeout: () => void) {
  let timeoutId: Timer | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<T>((_, reject) => {
        timeoutId = setTimeout(() => {
          onTimeout();
          reject(new Error(`Codex did not finish within ${Math.round(timeoutMs / 1000)}s`));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutId) clearTimeout(timeoutId);
  }
}

export function buildCodexPrompt(request: ChatRequest) {
  const sections: string[] = [];

  if (request.systemPrompt?.trim()) {
    sections.push(`Task instructions:\n${request.systemPrompt.trim()}`);
  }

  if (request.contextMessages?.length) {
    const transcript = request.contextMessages
      .map((message) => `${message.role === "user" ? "User" : "Assistant"}:\n${message.content}`)
      .join("\n\n");
    sections.push(`Previous conversation. Use this as context, but answer the current user message:\n${transcript}`);
  }

  if (request.files?.length) {
    const fileList = request.files.map((file) => `- ${file.path}${file.mimeType ? ` (${file.mimeType})` : ""}`).join("\n");
    sections.push(`Attached files:\n${fileList}`);
  }

  if (hasDetachBrowserTools(request)) {
    sections.push(browserToolInstructions());
  }

  if (hasDetachMacOSTools(request)) {
    sections.push(macOSToolInstructions());
  }

  if (hasDetachCapabilityBroker(request)) {
    sections.push(capabilityToolInstructions());
  }

  const composioInstructions = composioMCPInstructions(request.mcpServers);
  if (composioInstructions) {
    sections.push(composioInstructions);
  }

  sections.push(`Current user message:\n${request.text || ""}`);
  return sections.filter(Boolean).join("\n\n");
}

function resolveWorkspace(requested?: string) {
  if (requested?.trim()) return requested.trim();
  if (Bun.env.DETACH_WORKSPACE?.trim()) return Bun.env.DETACH_WORKSPACE.trim();
  return process.cwd();
}

function composioMCPInstructions(servers: MCPServerConfig[] = []) {
  const composio = servers.find((server) =>
    server.enabled &&
    server.name === "Composio MCP" &&
    server.toolNames?.includes("composio-direct-tools-v1")
  );
  if (!composio) return undefined;

  const toolkits = (composio.toolNames ?? [])
    .filter((name) => name.startsWith("composio-toolkit:"))
    .map((name) => name.slice("composio-toolkit:".length))
    .filter(Boolean);
  const toolkitText = toolkits.length > 0 ? ` Connected toolkit(s): ${toolkits.join(", ")}.` : "";

  return [
    `Composio MCP:${toolkitText}`,
    "- Treat this as the user's already-authorized Composio account surface; do not ask them to install a separate plugin.",
    "- Prefer concrete toolkit tools exposed by the Composio MCP server. Do not call COMPOSIO_MULTI_EXECUTE_TOOL for single-user requests like listing unread Gmail messages.",
    "- For read-only requests, keep calls narrow: discover the relevant concrete tool if needed, call it once with the smallest useful query/limit, then summarize the result.",
    "- If a concrete Composio tool fails or is missing, report the exact tool error instead of retrying broad helper tools repeatedly.",
  ].join("\n");
}
