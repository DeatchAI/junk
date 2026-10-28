import type { DemoCommand, DemoDraft, DemoFile } from "./demo-data";

export type EditorSelection = { start: number; end: number };
export type EditorTrigger = { kind: "attachments" | "commands"; query: string; start: number; end: number };
export type EditorToken = { key: string; marker: string; label: string; icon: string; file?: DemoFile; command?: DemoCommand };
export const tokenPattern = /\[\[(file|command):([^\]\n]+)\]\]/g;
export const fileMarker = (id: string) => `[[file:${id}]]`;
export const commandMarker = (id: string) => `[[command:${id}]]`;

export function editorTokens(draft: DemoDraft): EditorToken[] {
  return [
    ...draft.files.filter(file => file.kind !== "image").map(file => ({ key: `file:${file.id}`, marker: fileMarker(file.id), label: file.name, icon: file.icon ?? (file.kind === "chat" ? "chat" : "file"), file })),
    ...draft.commands.map(command => ({ key: `command:${command.id}`, marker: commandMarker(command.id), label: `/${command.command}`, icon: command.icon, command })),
  ];
}

export function editorDocument(draft: DemoDraft): string {
  let text = draft.text;
  for (const token of editorTokens(draft)) {
    if (text.includes(token.marker)) continue;
    if (text && !/\s$/.test(text)) text += " ";
    text += token.marker + " ";
  }
  return text;
}

export function readableDraft(draft: DemoDraft): string {
  return editorTokens(draft).reduce((text, token) => text.split(token.marker).join(token.file ? `@${token.label}` : token.label), editorDocument(draft)).trim();
}

export function findEditorTrigger(text: string, selection: EditorSelection): EditorTrigger | null {
  if (selection.start !== selection.end) return null;
  const prefix = text.slice(0, selection.start);
  const match = /([@/])([^\s@/\[\]]*)$/.exec(prefix);
  if (!match) return null;
  const start = match.index;
  return { kind: match[1] === "@" ? "attachments" : "commands", query: match[2], start, end: selection.start };
}

export function insertEditorToken(draft: DemoDraft, marker: string, selection: EditorSelection | null, trigger: EditorTrigger | null): { text: string; caret: number } {
  const text = editorDocument(draft);
  const start = Math.min(trigger?.start ?? selection?.start ?? text.length, text.length);
  const end = Math.min(trigger?.end ?? selection?.end ?? start, text.length);
  const insertion = marker ? `${marker} ` : "";
  return { text: text.slice(0, start) + insertion + text.slice(end), caret: start + insertion.length };
}

export function reconcileEditor(draft: DemoDraft, text: string): DemoDraft {
  return { text, files: draft.files.filter(file => file.kind === "image" || text.includes(fileMarker(file.id))),
    commands: draft.commands.filter(command => text.includes(commandMarker(command.id))) };
}

export function deleteEditorToken(text: string, selection: EditorSelection, backward: boolean, tokens: EditorToken[]): { text: string; caret: number } | null {
  if (selection.start !== selection.end) return null;
  for (const token of tokens) {
    if (backward) {
      const prefix = text.slice(0, selection.start);
      const end = prefix.endsWith(token.marker) ? prefix.length : prefix.endsWith(token.marker + " ") ? prefix.length - 1 : -1;
      if (end < 0) continue;
      const start = end - token.marker.length;
      return { text: text.slice(0, start) + text.slice(selection.start), caret: start };
    }
    const suffix = text.slice(selection.start);
    if (!suffix.startsWith(token.marker)) continue;
    const end = selection.start + token.marker.length + (suffix.startsWith(token.marker + " ") ? 1 : 0);
    return { text: text.slice(0, selection.start) + text.slice(end), caret: selection.start };
  }
  return null;
}
