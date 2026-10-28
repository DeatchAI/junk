import { iconPaths } from "./demo-icons";
import { tokenPattern, type EditorSelection, type EditorToken } from "./demo-editor-tokens";

export function readEditor(node: Node): string {
  if (node.nodeType === Node.TEXT_NODE) return node.textContent ?? "";
  if (node instanceof HTMLElement && node.dataset.editorToken) return node.dataset.editorToken;
  if (node instanceof HTMLBRElement) return "\n";
  let text = "";
  node.childNodes.forEach(child => {
    const block = child instanceof HTMLElement && ["DIV", "P"].includes(child.tagName);
    if (block && text && !text.endsWith("\n")) text += "\n";
    text += readEditor(child);
  });
  return text;
}

export function readEditorSelection(editor: HTMLElement): EditorSelection | null {
  const selection = document.getSelection();
  if (!selection?.rangeCount || !editor.contains(selection.anchorNode) || !editor.contains(selection.focusNode)) return null;
  const range = selection.getRangeAt(0);
  const before = range.cloneRange(); before.selectNodeContents(editor); before.setEnd(range.startContainer, range.startOffset);
  const through = range.cloneRange(); through.selectNodeContents(editor); through.setEnd(range.endContainer, range.endOffset);
  return { start: readEditor(before.cloneContents()).length, end: readEditor(through.cloneContents()).length };
}

export function restoreEditorSelection(editor: HTMLElement, position: EditorSelection) {
  const locate = (offset: number): { node: Node; offset: number } => {
    let remaining = Math.max(0, offset);
    const visit = (parent: Node): { node: Node; offset: number } | null => {
      for (const child of parent.childNodes) {
        if (child.nodeType === Node.TEXT_NODE) {
          const length = (child.textContent ?? "").length;
          if (remaining <= length) return { node: child, offset: remaining };
          remaining -= length;
        } else if (child instanceof HTMLElement && child.dataset.editorToken) {
          const index = [...parent.childNodes].indexOf(child);
          if (remaining === 0) return { node: parent, offset: index };
          const length = child.dataset.editorToken.length;
          if (remaining <= length) return { node: parent, offset: index + 1 };
          remaining -= length;
        } else {
          const result = visit(child); if (result) return result;
        }
      }
      return null;
    };
    return visit(editor) ?? { node: editor, offset: editor.childNodes.length };
  };
  const start = locate(position.start); const end = locate(position.end);
  const range = document.createRange(); range.setStart(start.node, start.offset); range.setEnd(end.node, end.offset);
  const selection = document.getSelection(); selection?.removeAllRanges(); selection?.addRange(range);
}

export function renderEditor(editor: HTMLElement, text: string, tokens: EditorToken[], className: string) {
  const fragment = document.createDocumentFragment();
  const known = new Map(tokens.map(token => [token.marker, token]));
  let offset = 0;
  for (const match of text.matchAll(tokenPattern)) {
    fragment.append(document.createTextNode(text.slice(offset, match.index)));
    const token = known.get(match[0]);
    if (!token) fragment.append(document.createTextNode(match[0]));
    else {
      const pill = document.createElement("span"); pill.contentEditable = "false"; pill.className = className;
      pill.dataset.editorToken = token.marker; pill.dataset.tokenKey = token.key;
      pill.setAttribute("role", "button"); pill.setAttribute("aria-label", token.file ? `Preview ${token.label}` : token.label);
      pill.title = token.file?.name ?? token.command?.subtitle ?? token.label;
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      for (const [key, value] of Object.entries({ width: "12", height: "12", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": "1.5", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true" })) svg.setAttribute(key, value);
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path"); path.setAttribute("d", iconPaths[token.icon as keyof typeof iconPaths] ?? iconPaths.file); svg.append(path);
      const label = document.createElement("span"); label.textContent = token.label;
      pill.append(svg, label); fragment.append(pill);
    }
    offset = match.index + match[0].length;
  }
  fragment.append(document.createTextNode(text.slice(offset)));
  editor.replaceChildren(fragment);
}
