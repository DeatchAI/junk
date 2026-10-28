"use client";

import { useRef, useState } from "react";
import { agents, emptyBranch, historyItems, sampleConversation, sampleFiles, sampleRuns, type AgentId, type DemoBranch, type DemoCommand, type DemoDraft, type DemoFile, type DemoMenu, type DemoMessage } from "./demo-data";
import type { DemoWindowSpec, DemoWorkspace, SharedDemoState } from "./demo-workspace";
import { commandMarker, editorDocument, fileMarker, findEditorTrigger, insertEditorToken, readableDraft, reconcileEditor, type EditorSelection, type EditorTrigger } from "./demo-editor-tokens";

type Revision = { index: number; savedDraft: DemoDraft };
type ComposerState = {
  branches: DemoBranch[]; branchId: string; conversationId: string; agent: AgentId; model: string; project: string;
  effort: string; permission: string; menu: DemoMenu; expanded: boolean; revision: Revision | null; documentVersion: number; attachmentSection: string | null;
  editorSelection: EditorSelection | null; trigger: EditorTrigger | null;
};
type Patch = Partial<ComposerState & Pick<SharedDemoState, "historyOpen" | "islandOpen" | "appearance" | "projects" | "customCommands" | "mcpServers" | "previewFile"> & { composerOpen: boolean }>;

function initialComposer(spec: DemoWindowSpec): ComposerState {
  const hasHistory = spec.seed || historyItems.some(item => item.id === spec.conversationId);
  const messages = spec.messages?.map(message => ({ ...message, files: [...message.files] }))
    ?? (hasHistory ? sampleConversation(spec.agent).map((message, index) => ({ ...message, id: `${spec.conversationId}-u${index}` })) : []);
  if (hasHistory && !spec.seed && !spec.messages) {
    messages[0] = { ...messages[0], prompt: spec.title, files: [] };
    messages[1] = { ...messages[1], prompt: "Keep the changes focused and follow the existing conventions.", files: [sampleFiles[1]],
      answer: sampleRuns.some(run => run.conversationId === spec.conversationId && run.state === "running") ? "" : "I’ll keep the changes focused and follow the project’s existing conventions." };
  }
  const original = { ...emptyBranch(`${spec.conversationId}-original`), messages, selected: messages.length - 1 };
  if (spec.draftText) original.draft = { ...original.draft, text: spec.draftText };
  const branches = [original];
  if (spec.seed) {
    original.draft = { text: "Give this page a little more breathing room.", files: [sampleFiles[0], sampleFiles[1]], commands: [] };
    branches.push({ ...emptyBranch(`${spec.conversationId}-alternate`), label: "Edited message 2", selected: 1,
      messages: [messages[0], { ...messages[1], id: `${spec.conversationId}-alternate-u1`, prompt: "Keep the project cards in a single column. Use the same reference.", answer: "I’ll keep the single-column layout and use the reference for the spacing." }] });
  }
  for (const item of branches) item.draft.text = editorDocument(item.draft);
  return { branches, branchId: original.id, conversationId: spec.conversationId, agent: spec.agent,
    model: spec.model ?? agents.find(agent => agent.id === spec.agent)!.models[0], project: spec.project, effort: "Auto", permission: "Agent default",
    menu: null, expanded: false, revision: null, documentVersion: 0, attachmentSection: null, editorSelection: null, trigger: null };
}

export function useDemo(spec: DemoWindowSpec, workspace: DemoWorkspace) {
  const [stored, setState] = useState(() => initialComposer(spec));
  const sequence = useRef(0);
  const branch = stored.branches.find(item => item.id === stored.branchId)!;
  const currentRun = workspace.state.runs.find(run => run.conversationId === stored.conversationId && (!run.branchId || run.branchId === stored.branchId));
  const activeRun = currentRun && ["running", "approval", "question"].includes(currentRun.state) ? currentRun : null;
  const state = { ...stored, ...workspace.state, windowId: spec.id, composerOpen: spec.visible, run: activeRun,
    phase: currentRun?.state === "stopped" ? "stopped" : activeRun ? "running" : "done", activity: currentRun?.activity ?? "" };

  function patch(values: Patch) {
    const { historyOpen, islandOpen, appearance, projects, customCommands, mcpServers, previewFile, composerOpen, ...local } = values;
    const shared: Partial<SharedDemoState> = {};
    if (historyOpen !== undefined) shared.historyOpen = historyOpen;
    if (islandOpen !== undefined) shared.islandOpen = islandOpen;
    if (appearance !== undefined) shared.appearance = appearance;
    if (projects !== undefined) shared.projects = projects;
    if (customCommands !== undefined) shared.customCommands = customCommands;
    if (mcpServers !== undefined) shared.mcpServers = mcpServers;
    if (previewFile !== undefined) shared.previewFile = previewFile;
    if (Object.keys(shared).length) workspace.patch(shared);
    if (composerOpen === false) workspace.hideWindow(spec.id);
    if (composerOpen === true) workspace.focusWindow(spec.id);
    if (local.agent !== undefined || local.project !== undefined || local.model !== undefined) workspace.updateWindow(spec.id, {
      ...(local.agent !== undefined ? { agent: local.agent } : {}), ...(local.project !== undefined ? { project: local.project } : {}),
      ...(local.model !== undefined ? { model: local.model } : {}),
    });
    if (Object.keys(local).length) setState(current => ({ ...current, ...local }));
  }
  function changeBranch(update: (value: DemoBranch) => DemoBranch) {
    setState(current => ({ ...current, branches: current.branches.map(item => item.id === current.branchId ? update(item) : item) }));
  }

  function send() {
    if (activeRun || (!branch.draft.text.trim() && !branch.draft.files.length && !branch.draft.commands.length)) return;
    const message: DemoMessage = { id: `${spec.id}-message-${++sequence.current}`, prompt: readableDraft(branch.draft), editorText: editorDocument(branch.draft), files: [...branch.draft.files],
      commands: [...branch.draft.commands], agent: stored.agent, answer: "" };
    let branchId = branch.id;
    let branches: DemoBranch[];
    if (stored.revision) {
      branchId = `${spec.id}-branch-${++sequence.current}`;
      branches = [...stored.branches.map(item => item.id === branch.id ? { ...item, draft: stored.revision!.savedDraft } : item),
        { id: branchId, label: `Edited message ${stored.revision.index + 1}`, messages: [...branch.messages.slice(0, stored.revision.index), message],
          draft: { ...stored.revision.savedDraft, files: [...stored.revision.savedDraft.files], commands: [...stored.revision.savedDraft.commands] }, selected: stored.revision.index }];
    } else branches = stored.branches.map(item => item.id !== branch.id ? item : { ...item, messages: [...item.messages, message], draft: { text: "", files: [], commands: [] }, selected: item.messages.length });
    patch({ branches, branchId, revision: null, menu: null, trigger: null, editorSelection: null, historyOpen: false, documentVersion: stored.documentVersion + 1 });
    const target = branchId;
    workspace.startRun({ windowId: spec.id, conversationId: stored.conversationId, branchId, messageId: message.id, agent: stored.agent,
      project: stored.project, prompt: message.prompt }, () => {
      setState(current => ({ ...current, branches: current.branches.map(item => item.id !== target ? item : { ...item,
        messages: item.messages.map(value => value.id !== message.id ? value : { ...value, answer: "I’ll keep the changes focused and follow the project’s existing conventions." }) }) }));
    });
  }

  function edit(index: number) {
    const message = branch.messages[index]; if (activeRun || !message) return;
    const savedDraft = stored.revision?.savedDraft ?? branch.draft;
    const draft = { text: message.editorText ?? message.prompt, files: [...message.files], commands: [...(message.commands ?? [])] };
    draft.text = editorDocument(draft);
    patch({ revision: { index, savedDraft }, menu: null, trigger: null, editorSelection: null, documentVersion: stored.documentVersion + 1,
      branches: stored.branches.map(item => item.id !== stored.branchId ? item : { ...item, draft }) });
  }
  function cancelEdit() {
    if (!stored.revision) return;
    patch({ revision: null, menu: null, trigger: null, editorSelection: null, documentVersion: stored.documentVersion + 1,
      branches: stored.branches.map(item => item.id !== stored.branchId ? item : { ...item, draft: stored.revision!.savedDraft }) });
  }
  function switchBranch(id: string) {
    if (activeRun || id === stored.branchId) return;
    patch({ branchId: id, revision: null, menu: null, trigger: null, editorSelection: null, documentVersion: stored.documentVersion + 1,
      branches: stored.revision ? stored.branches.map(item => item.id !== stored.branchId ? item : { ...item, draft: stored.revision!.savedDraft }) : stored.branches });
  }
  function updateEditor(text: string, selection: EditorSelection, replace = false) {
    setState(current => {
      const draft = current.branches.find(item => item.id === current.branchId)!.draft;
      if (!replace && draft.text === text && current.editorSelection?.start === selection.start && current.editorSelection.end === selection.end) return current;
      const trigger = replace ? null : findEditorTrigger(text, selection);
      const picker = current.menu === "attachments" || current.menu === "commands";
      const menu = trigger && (!current.menu || picker) ? trigger.kind : !trigger && current.trigger && picker ? null : current.menu;
      return { ...current, editorSelection: selection, trigger, menu, documentVersion: current.documentVersion + (replace ? 1 : 0),
        branches: current.branches.map(item => item.id !== current.branchId ? item : { ...item, draft: reconcileEditor(item.draft, text) }) };
    });
  }
  function insertToken(file?: DemoFile, command?: DemoCommand, keepOpen = false) {
    setState(current => {
      const draft = current.branches.find(item => item.id === current.branchId)!.draft;
      const duplicate = file ? draft.files.some(item => item.id === file.id) : draft.commands.some(item => item.id === command!.id);
      const marker = duplicate || file?.kind === "image" ? "" : file ? fileMarker(file.id) : commandMarker(command!.id);
      const insertion = insertEditorToken(draft, marker, current.editorSelection, current.trigger);
      const next = { text: insertion.text, files: file && !duplicate ? [...draft.files, file] : draft.files,
        commands: command && !duplicate ? [...draft.commands, command] : draft.commands };
      return { ...current, menu: keepOpen ? current.menu : null, trigger: null, attachmentSection: null,
        editorSelection: { start: insertion.caret, end: insertion.caret }, documentVersion: current.documentVersion + 1,
        branches: current.branches.map(item => item.id !== current.branchId ? item : { ...item, draft: reconcileEditor(next, next.text) }) };
    });
  }
  function removeToken(id: string, kind: "file" | "command") {
    setState(current => ({ ...current, menu: null, trigger: null, editorSelection: null, documentVersion: current.documentVersion + 1,
      branches: current.branches.map(item => {
        if (item.id !== current.branchId) return item;
        const marker = kind === "file" ? fileMarker(id) : commandMarker(id);
        const text = editorDocument(item.draft).split(marker).join("");
        return { ...item, draft: { ...reconcileEditor(item.draft, text), files: kind === "file" ? item.draft.files.filter(file => file.id !== id) : item.draft.files } };
      }) }));
  }
  const attach = (file: DemoFile) => insertToken(file);
  const attachCommand = (command: DemoCommand) => insertToken(undefined, command);
  function closeMenu() { if (stored.menu) patch({ menu: null }); }
  function dismissTransient() {
    if (stored.menu) { closeMenu(); return true; }
    if (stored.revision) { cancelEdit(); return true; }
    return false;
  }

  return { state, branch, patch, send, edit, cancelEdit, switchBranch, attach, attachCommand, closeMenu, dismissTransient, updateEditor, placeholder: spec.placeholder ?? "Anything ..",
    newChat: () => workspace.addComposer(), allCommands: workspace.allCommands, conversations: workspace.conversations,
    selectAgent: (id: AgentId) => patch({ agent: id, model: agents.find(agent => agent.id === id)!.models[0] }),
    stop: () => { if (activeRun) workspace.stopRun(activeRun.id); },
    createCommand: (command: DemoCommand) => { patch({ customCommands: [...workspace.state.customCommands, command] }); attachCommand(command); },
    removeFile: (id: string) => removeToken(id, "file"),
    toggleContext: (file: DemoFile) => branch.draft.files.some(value => value.id === file.id) ? removeToken(file.id, "file") : insertToken(file, undefined, true),
    selectMessage: (selected: number) => changeBranch(item => ({ ...item, selected })) };
}

export type DemoController = ReturnType<typeof useDemo>;
