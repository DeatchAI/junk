import type { AgentActivityEvent } from "../../protocol/messages";
import { shortPath, summarizeShellCommand as summarizeCommand } from "../CliAdapterUtils";

export type CodexExecEvent = {
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
          command: item.command,
          output: item.aggregated_output,
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

function codexItemPhase(event: CodexExecEvent): AgentActivityEvent["phase"] {
  const status = event.item?.status;
  if (status === "failed") return "failed";
  if (status === "completed") return "completed";
  if (status === "in_progress") return "started";
  if (event.type === "item.started") return "started";
  if (event.type === "item.completed") return "completed";
  return "updated";
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

function humanizeIdentifier(value: string) {
  return value.replace(/^detach_/, "").replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

