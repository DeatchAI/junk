import type { AgentActivityEvent, MessagePart } from "../protocol/messages";

/** One provider-independent ledger for live replies and the offline history mirror. */
export class ResponseTranscript {
  readonly parts: MessagePart[] = [];
  private readonly tools = new Map<string, MessagePart>();
  text(value: string) {
    if (!value) return;
    const last = this.parts.at(-1);
    if (last?.type === "text") last.text = (last.text ?? "") + value;
    else this.parts.push({ type: "text", text: value });
  }
  activity(event: AgentActivityEvent) {
    if (!event.userFacing || ["lifecycle", "status"].includes(event.kind)) return;
    const details = event.details ?? {};
    const part: MessagePart = { type: "activity", id: event.id, kind: event.kind, title: event.title,
      status: event.phase, toolName: event.toolName,
      command: typeof details.command === "string" ? details.command : undefined,
      output: typeof details.output === "string" ? details.output : undefined,
      text: Object.keys(details).length ? JSON.stringify(details, null, 2) : event.subtitle };
    const previous = event.id ? this.tools.get(event.id) : undefined;
    if (previous) Object.assign(previous, part);
    else { this.parts.push(part); if (event.id) this.tools.set(event.id, part); }
  }
  finish() {
    // End the live indicator without inventing a successful tool result.
    for (const part of this.parts) {
      if (part.type === "activity" && ["started", "updated", "in_progress"].includes(part.status ?? "")) part.status = "finished";
    }
  }
}
