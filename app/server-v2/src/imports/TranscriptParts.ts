import type { MessagePart } from "../protocol/messages";
import { contentText, record, text } from "./Transcript";

/** Display data only. Tool payloads never become assistant prose or executable actions. */
export function activityPart(kind: string, title: string, values: Partial<MessagePart> = {}): MessagePart {
  return { type: "activity", kind, title, status: "completed", ...values };
}

export function commandTitle(command: string) {
  // Compound shell programs need a bounded label, not a lossy rewrite of their script.
  if (/\b(xcodebuild|swift build|bun run build|npm run build)\b/.test(command)) return "Built the app";
  if (/\b(test|pytest|swift test)\b/.test(command)) return "Ran tests";
  if (/\b(rg|grep|find)\b/.test(command)) return "Searched files";
  if (/\b(sed|cat|head|tail)\b/.test(command)) return "Read files";
  if (/\bls\b/.test(command)) return "Listed files";
  return "Ran command";
}

export function toolPart(name: string, input?: unknown, values: Partial<MessagePart> = {}) {
  const args = record(input);
  const command = text(args.command ?? args.cmd);
  const path = text(args.file_path ?? args.path ?? args.filePath);
  const kind = /bash|shell|exec|terminal/i.test(name) ? "command"
    : /read|list/i.test(name) ? "read" : /search|grep|find/i.test(name) ? "search"
    : /edit|write|patch/i.test(name) ? "file_change" : "tool";
  const title = kind === "command" ? commandTitle(command) : kind === "read" ? (path ? `Read ${path.split("/").at(-1)}` : "Read files")
    : kind === "search" ? "Searched files" : kind === "file_change" ? "Updated files" : "Used tool";
  return activityPart(kind, title, { toolName: name, command: command || undefined,
    text: input === undefined ? undefined : JSON.stringify(input, null, 2), ...values });
}

export function contentParts(content: unknown): MessagePart[] {
  if (typeof content === "string") return content ? [{ type: "text", text: content }] : [];
  if (!Array.isArray(content)) return [];
  return content.flatMap((raw): MessagePart[] => {
    const block = record(raw);
    if (["text", "input_text", "output_text"].includes(block.type)) return [{ type: "text", text: text(block.text) }];
    if (["image", "localImage", "input_image", "file"].includes(block.type)) {
      return [{ type: "text", text: "[Attachment in original session; file not copied]" }];
    }
    if (["tool_use", "toolCall", "tool_call"].includes(block.type)) {
      return [toolPart(text(block.name), block.input ?? block.arguments, { id: text(block.id) || undefined })];
    }
    if (block.type === "tool_result") return [activityPart("tool", "Tool result", {
      id: text(block.tool_use_id) || undefined, output: contentText(block.content),
      status: block.is_error ? "failed" : "completed",
    })];
    return []; // Reasoning and unknown provider envelopes are not conversation text.
  });
}

export function readableText(parts: MessagePart[]) {
  return parts.filter((part) => part.type === "text").map((part) => part.text ?? "").filter(Boolean).join("\n\n");
}

export function mergeParts(parts: MessagePart[]) {
  const result: MessagePart[] = [];
  const tools = new Map<string, MessagePart>();
  for (const part of parts) {
    const previous = part.type === "activity" && part.id ? tools.get(part.id) : undefined;
    if (previous) {
      if (part.output !== undefined) previous.output = part.output;
      if (part.status) previous.status = part.status;
    } else {
      const copy = { ...part }; result.push(copy);
      if (part.type === "activity" && part.id) tools.set(part.id, copy);
    }
  }
  return result;
}
