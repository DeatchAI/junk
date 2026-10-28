import type { AgentStreamCallbacks } from "../AgentAdapter";
import { asStringRecord as record, getString } from "../CliAdapterUtils";
import { codexActivityFromEvent, type CodexExecEvent } from "./CodexActivity";

export class CodexNotifications {
  readonly items = new Map<string, Record<string, unknown>>();
  private readonly messages = new Map<string, string>();

  constructor(private readonly callbacks: AgentStreamCallbacks) {}

  get text() {
    return [...this.messages.values()].filter(Boolean).join("\n\n");
  }

  handle(method: string, params: Record<string, unknown>) {
    if (method === "item/agentMessage/delta") {
      const id = getString(params.itemId);
      const delta = getString(params.delta);
      if (id && delta) this.updateText(id, `${this.messages.get(id) ?? ""}${delta}`);
      return;
    }

    const item = record(params.item);
    const id = getString(item?.id);
    if (!item || !id || !["item/started", "item/completed"].includes(method)) return;
    this.items.set(id, item);
    if (item.type === "agentMessage") {
      if (method === "item/completed" && typeof item.text === "string") this.updateText(id, item.text);
      return;
    }

    const event = codexActivityFromEvent({
      type: method.replace("/", "."),
      item: activityItem(item),
    });
    if (event?.userFacing) this.callbacks.onActivity(event.title, event.toolName, event);
  }

  private updateText(id: string, text: string) {
    const previous = this.messages.get(id) ?? "";
    const separator = !previous && this.text ? "\n\n" : "";
    this.messages.set(id, text);
    if (text.startsWith(previous) && text.length > previous.length) {
      this.callbacks.onChunk(`${separator}${text.slice(previous.length)}`);
    }
  }
}

function activityItem(item: Record<string, unknown>): CodexExecEvent["item"] {
  const types: Record<string, string> = {
    commandExecution: "command_execution",
    fileChange: "file_change",
    mcpToolCall: "mcp_tool_call",
  };
  const changes = Array.isArray(item.changes) ? item.changes.map((value) => {
    const change = record(value);
    return {
      path: getString(change?.path),
      kind: getString(change?.kind) || getString(record(change?.kind)?.type),
    };
  }) : undefined;
  const status = getString(item.status);
  return {
    id: getString(item.id),
    type: types[String(item.type)] || getString(item.type),
    command: getString(item.command),
    status: status === "inProgress" ? "in_progress" : status === "declined" ? "failed" : status,
    aggregated_output: getString(item.aggregatedOutput),
    exit_code: typeof item.exitCode === "number" ? item.exitCode : undefined,
    changes,
    server: getString(item.server),
    tool: getString(item.tool),
    arguments: item.arguments,
    result: item.result,
    error: item.error,
  };
}
