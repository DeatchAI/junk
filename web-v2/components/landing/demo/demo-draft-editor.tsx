import { useEffect, useLayoutEffect, useRef, type KeyboardEvent, type RefObject } from "react";
import { readEditor, readEditorSelection, renderEditor, restoreEditorSelection } from "./demo-editor-dom";
import { deleteEditorToken, editorDocument, editorTokens } from "./demo-editor-tokens";
import type { DemoController } from "./use-demo";
import { composerClasses as c } from "./demo-classes";
import p from "./demo-panels.module.css";

export function DraftEditor({ demo, editorRef }: { demo: DemoController; editorRef: RefObject<HTMLDivElement | null> }) {
  const version = useRef(demo.state.documentVersion);
  const draft = demo.branch.draft;
  const text = editorDocument(draft);

  useLayoutEffect(() => {
    const editor = editorRef.current; if (!editor) return;
    const changed = version.current !== demo.state.documentVersion;
    const selection = changed ? demo.state.editorSelection : readEditorSelection(editor);
    if (readEditor(editor) !== text) renderEditor(editor, text, editorTokens(draft), p.editorToken);
    if (changed) {
      version.current = demo.state.documentVersion;
      editor.focus({ preventScroll: true });
      restoreEditorSelection(editor, selection ?? { start: text.length, end: text.length });
    }
  }, [demo.state.documentVersion, demo.state.editorSelection, draft, editorRef, text]);

  useEffect(() => {
    function trackSelection() {
      const editor = editorRef.current;
      if (!editor || document.activeElement !== editor) return;
      const selection = readEditorSelection(editor);
      if (selection) demo.updateEditor(readEditor(editor), selection);
    }
    document.addEventListener("selectionchange", trackSelection);
    return () => document.removeEventListener("selectionchange", trackSelection);
  }, [demo, editorRef]);

  function input() {
    const editor = editorRef.current; if (!editor) return;
    const value = readEditor(editor);
    demo.updateEditor(value, readEditorSelection(editor) ?? { start: value.length, end: value.length });
  }
  function keyDown(event: KeyboardEvent<HTMLDivElement>) {
    if (event.nativeEvent.isComposing) return;
    if ((event.key === "Backspace" || event.key === "Delete") && !event.metaKey && !event.ctrlKey && !event.altKey) {
      const selection = readEditorSelection(event.currentTarget);
      const removal = selection && deleteEditorToken(readEditor(event.currentTarget), selection, event.key === "Backspace", editorTokens(draft));
      if (removal) {
        event.preventDefault();
        demo.updateEditor(removal.text, { start: removal.caret, end: removal.caret }, true);
        return;
      }
    }
    if (event.key === "Enter" && !event.shiftKey && !demo.state.menu) { event.preventDefault(); demo.send(); }
  }

  return <div ref={editorRef} className={c.editor} contentEditable role="textbox" aria-label="Message your agent" aria-multiline="true"
    data-placeholder={demo.placeholder} suppressContentEditableWarning spellCheck={false} onKeyDown={keyDown} onInput={input}
    onMouseDown={event => { if ((event.target as Element).closest("[data-editor-token]")) event.preventDefault(); }}
    onClick={event => {
      const key = (event.target as Element).closest<HTMLElement>("[data-editor-token]")?.dataset.tokenKey;
      const file = draft.files.find(item => key === `file:${item.id}`);
      if (file) demo.patch({ previewFile: file, menu: null });
    }}
    onPaste={event => {
      event.preventDefault();
      const selection = document.getSelection();
      if (!selection?.rangeCount) return;
      const range = selection.getRangeAt(0); range.deleteContents();
      const pasted = document.createTextNode(event.clipboardData.getData("text/plain"));
      range.insertNode(pasted); range.setStartAfter(pasted); range.collapse(true); selection.removeAllRanges(); selection.addRange(range);
      input();
    }}/>;
}
