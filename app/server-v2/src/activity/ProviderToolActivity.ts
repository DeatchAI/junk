import type { AgentActivityEvent, AgentKind } from "../protocol/messages";
import type { AgentStreamCallbacks } from "../agents/AgentAdapter";
import { activityPart, toolPart } from "../imports/TranscriptParts";
import { contentText, record, text } from "../imports/Transcript";

/** Tools from block-based and RPC providers share the same display contract. */
export class ProviderToolActivity {
  private calls = new Map<string, { name: string; input: unknown }>();
  constructor(private readonly agent: AgentKind, private readonly callbacks: AgentStreamCallbacks) {}

  start(name: string, input: unknown, id?: string) {
    if (id) this.calls.set(id, { name, input });
    this.publish(name, input, id, "started");
  }
  finish(id: string | undefined, output: string, failed = false, name = "Tool") {
    const call = id ? this.calls.get(id) : undefined;
    this.publish(call?.name ?? name, call?.input, id, failed ? "failed" : "completed", output);
  }
  blocks(content: unknown) {
    if (!Array.isArray(content)) return;
    for (const raw of content) {
      const block = record(raw);
      if (block.type === "tool_use") this.start(text(block.name), block.input, text(block.id) || undefined);
      if (block.type === "tool_result") this.finish(text(block.tool_use_id) || undefined, contentText(block.content), block.is_error === true);
    }
  }
  private publish(name: string, input: unknown, id: string | undefined, phase: AgentActivityEvent["phase"], output?: string) {
    const part = input === undefined && name === "Tool" ? activityPart("tool", "Tool result") : toolPart(name, input);
    const event: AgentActivityEvent = { agent: this.agent, id, kind: part.kind === "command" ? "command"
      : part.kind === "file_change" ? "file_change" : "mcp_tool", phase, title: part.title ?? "Used tool",
      toolName: name, userFacing: true, details: { input, command: part.command, output } };
    this.callbacks.onActivity(event.title, name, event);
  }
}
