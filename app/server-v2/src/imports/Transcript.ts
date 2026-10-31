import { createHash } from "node:crypto";
import { stat } from "node:fs/promises";
import { isAbsolute } from "node:path";
import type { ImportedMessage } from "./ImportTypes";
import { mergeParts, readableText } from "./TranscriptParts";

export const MAX_TRANSCRIPT_BYTES = 16 * 1024 * 1024;
export const MAX_DISCOVERY = 10_000;
export const record = (value: unknown): Record<string, any> => value && typeof value === "object" && !Array.isArray(value) ? value as any : {};
export const text = (value: unknown): string => typeof value === "string" ? value : "";
export function parseLines(value: string) {
  return value.split(/\r?\n/).flatMap((line) => { try { return [record(JSON.parse(line))]; } catch { return []; } });
}
export function transcriptLines(value: string) {
  const lines = value.split(/\r?\n/);
  for (const [index, line] of lines.entries()) {
    if (!line.trim()) continue;
    try { JSON.parse(line); }
    catch { if (index !== lines.length - 1) throw new Error("Provider transcript contains malformed records."); }
  }
  return parseLines(value);
}
export function timestamp(value: unknown, fallback = Date.now()): number {
  const numeric = typeof value === "string" ? Date.parse(value) : typeof value === "number" ? value : NaN;
  if (!Number.isFinite(numeric) || numeric <= 0) return fallback;
  return Math.round(numeric < 100_000_000_000 ? numeric * 1000 : numeric);
}
export function sourceKey(provider: string, namespace: string, id: string) {
  return createHash("sha256").update(JSON.stringify([provider, namespace, id])).digest("hex");
}
export async function existingWorkspace(path: unknown) {
  if (typeof path !== "string" || !isAbsolute(path)) return undefined;
  return (await stat(path).catch(() => undefined))?.isDirectory() ? path : undefined;
}
export function contentText(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content.map((raw) => {
    const block = record(raw);
    if (["text", "input_text", "output_text"].includes(block.type)) return text(block.text);
    if (["image", "localImage", "input_image", "file"].includes(block.type)) return "[Attachment in original session; file not copied]";
    if (block.type === "tool_result") return `[Tool result]\n${contentText(block.content)}`;
    if (block.type === "tool_use") return `[Tool: ${text(block.name) || "tool"}]\n${JSON.stringify(block.input ?? {})}`;
    return "";
  }).filter(Boolean).join("\n\n");
}
export function normalizeMessages(messages: ImportedMessage[]) {
  const result: ImportedMessage[] = [];
  let size = 0;
  for (const message of messages) {
    if (!message.content.trim() && !message.parts?.length) continue;
    size += Buffer.byteLength(message.content) + Buffer.byteLength(JSON.stringify(message.parts ?? []));
    if (size > MAX_TRANSCRIPT_BYTES || result.length >= 10_000) throw new Error("This conversation is too large to import safely.");
    const last = result.at(-1);
    if (last?.role === message.role) {
      if (message.role === "assistant" && message.branchPoint) last.branchPoint = message.branchPoint;
      if (last.parts || message.parts) {
        last.parts = mergeParts([...(last.parts ?? [{ type: "text", text: last.content }]),
          ...(message.parts ?? [{ type: "text", text: message.content }])]);
        last.content = readableText(last.parts);
      } else last.content += `\n\n${message.content}`;
    } else result.push({ ...message, ...(message.parts ? { parts: mergeParts(message.parts) } : {}) });
  }
  if (!result.length) throw new Error("No readable messages were found in this session.");
  return result;
}
export function title(value: unknown, fallback = "Imported conversation") {
  return (text(value).replace(/[\u0000-\u001f\u007f]/g, " ").trim() || fallback).slice(0, 160);
}
