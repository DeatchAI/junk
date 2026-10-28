"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { agents, commands, historyItems, sampleConnections, sampleRuns, type AgentId, type DemoCommand, type DemoFile, type DemoMessage, type DemoRun } from "./demo-data";

export type DemoWindowSpec = { id: string; conversationId: string; title: string; project: string; agent: AgentId; model?: string; visible: boolean; order: number; focusVersion: number; seed?: boolean; draftText?: string; placeholder?: string; messages?: DemoMessage[]; offset: { x: number; y: number } };
export type WindowHandle = { dismissTransient: () => boolean; closeMenu: () => void; selectBranch: (id: string) => void };
export type SharedDemoState = {
  windows: DemoWindowSpec[]; activeWindowId: string; historyOpen: boolean; islandOpen: boolean;
  appearance: "dark" | "light"; projects: string[]; customCommands: DemoCommand[]; mcpServers: DemoFile[]; previewFile: DemoFile | null; runs: DemoRun[]; generation: number;
};
type RunRequest = { windowId: string; conversationId: string; branchId: string; messageId: string; agent: AgentId; project: string; prompt: string };

function initialState(): SharedDemoState {
  return { windows: [{ id: "composer-1", conversationId: "landing", title: "Polish the landing page", project: "acme", agent: "codex", visible: true, order: 1, focusVersion: 0, seed: true, offset: { x: 0, y: 0 } }],
    activeWindowId: "composer-1", historyOpen: false, islandOpen: false, appearance: "dark", projects: ["acme", "portfolio", "side-project"], customCommands: [], mcpServers: [...sampleConnections], previewFile: null, runs: sampleRuns.map(run => ({ ...run })), generation: 0 };
}

export function useDemoWorkspace(initialOverrides?: Partial<SharedDemoState>) {
  const [state, setState] = useState(() => ({ ...initialState(), ...initialOverrides }));
  const sequence = useRef(1);
  const layers = useRef(1);
  const handles = useRef(new Map<string, WindowHandle>());
  const timers = useRef(new Map<string, ReturnType<typeof setTimeout>>());
  const replies = useRef(new Map<string, () => void>());
  const allCommands = useMemo(() => [...commands, ...state.customCommands], [state.customCommands]);
  const activeWindow = state.windows.find(window => window.id === state.activeWindowId);
  const conversations = [...historyItems];
  for (const window of state.windows) {
    if (!conversations.some(item => item.id === window.conversationId) && window.title !== "New chat")
      conversations.unshift({ id: window.conversationId, title: window.title, project: window.project || "Conversations", agent: window.agent });
  }

  useEffect(() => {
    const runningTimers = timers.current;
    return () => { runningTimers.forEach(clearTimeout); };
  }, []);

  function patch(values: Partial<SharedDemoState>) { setState(current => ({ ...current, ...values })); }
  function register(id: string, handle: WindowHandle) { handles.current.set(id, handle); return () => { handles.current.delete(id); }; }
  function updateWindow(id: string, values: Partial<Pick<DemoWindowSpec, "agent" | "model" | "project">>) {
    setState(current => ({ ...current, windows: current.windows.map(window => window.id === id ? { ...window, ...values } : window) }));
  }
  function closeMenus(except?: string) { handles.current.forEach((handle, id) => { if (id !== except) handle.closeMenu(); }); }

  function focusWindow(id: string) {
    closeMenus(id);
    setState(current => {
      if (current.activeWindowId === id && current.windows.find(window => window.id === id)?.visible) return current;
      const order = ++layers.current;
      return { ...current, activeWindowId: id, windows: current.windows.map(window => window.id !== id ? window : { ...window, visible: true, order }) };
    });
  }

  function addComposer(conversationId?: string) {
    closeMenus();
    const existing = conversationId && state.windows.find(window => window.conversationId === conversationId);
    if (existing) {
      const order = ++layers.current;
      setState(current => ({ ...current, activeWindowId: existing.id, historyOpen: false, islandOpen: false,
        windows: current.windows.map(window => window.id !== existing.id ? window : { ...window, visible: true, order, focusVersion: window.focusVersion + 1 }) }));
      return existing.id;
    }
    const serial = ++sequence.current;
    const id = `composer-${serial}`;
    const item = conversations.find(item => item.id === conversationId);
    const run = state.runs.find(candidate => candidate.conversationId === conversationId);
    const agent = item?.agent ?? run?.agent ?? activeWindow?.agent ?? "codex";
    const window: DemoWindowSpec = { id, conversationId: conversationId ?? `conversation-${serial}`, title: item?.title ?? run?.title ?? "New chat",
      agent, project: item?.project ?? run?.project ?? activeWindow?.project ?? "acme", visible: true,
      model: item || run ? agents.find(candidate => candidate.id === agent)!.models[0] : activeWindow?.model,
      ...(run && !item ? { messages: [{ id: run.messageId, prompt: run.title, files: [], answer: "", agent }] } : {}),
      order: ++layers.current, focusVersion: 1, offset: { x: ((serial - 1) % 5) * 24, y: -((serial - 1) % 5) * 22 } };
    setState(current => ({ ...current, windows: [...current.windows, window], activeWindowId: id, historyOpen: false, islandOpen: false }));
    return id;
  }

  function hideWindow(id: string) {
    handles.current.get(id)?.closeMenu();
    setState(current => {
      const windows = current.windows.map(window => window.id !== id ? window : { ...window, visible: false });
      const next = windows.filter(window => window.visible).sort((a, b) => b.order - a.order)[0];
      return { ...current, windows, activeWindowId: next?.id ?? "" };
    });
  }

  function dismissFrontComposer() {
    const front = state.windows.filter(window => window.visible).sort((a, b) => b.order - a.order)[0];
    if (!front) return;
    if (!handles.current.get(front.id)?.dismissTransient()) hideWindow(front.id);
  }

  function scheduleRun(run: DemoRun) {
    const previous = timers.current.get(run.id); if (previous) clearTimeout(previous);
    timers.current.set(run.id, setTimeout(() => {
      if (!timers.current.has(run.id)) return;
      timers.current.delete(run.id);
      setState(current => ({ ...current, runs: current.runs.map(item => item.id !== run.id ? item : { ...item, state: "completed", activity: "Completed" }) }));
      replies.current.get(run.id)?.();
    }, 4000));
  }

  function startRun(request: RunRequest, onComplete: () => void) {
    const run: DemoRun = { id: `${request.windowId}-${request.messageId}`, title: request.prompt.trim().split("\n")[0].slice(0, 60) || "Review attached context",
      agent: request.agent, conversationId: request.conversationId, messageId: request.messageId, windowId: request.windowId,
      branchId: request.branchId, state: "running", activity: "Working on your task" };
    replies.current.set(run.id, onComplete);
    setState(current => ({ ...current, runs: [run, ...current.runs], windows: current.windows.map(window => window.id !== request.windowId ? window : {
      ...window, title: run.title, agent: request.agent, project: request.project }) }));
    scheduleRun(run);
  }

  function stopRun(id: string) {
    const timer = timers.current.get(id); if (timer) clearTimeout(timer); timers.current.delete(id);
    setState(current => ({ ...current, runs: current.runs.map(run => run.id !== id ? run : { ...run, state: "stopped", activity: "Stopped" }) }));
  }
  function resolveAttention(id: string, proceed: boolean) {
    const run = state.runs.find(item => item.id === id);
    if (!run || (run.state !== "approval" && run.state !== "question")) return;
    const next: DemoRun = { ...run, state: proceed ? "running" : "stopped", activity: proceed ? "Continuing the task" : "Stopped" };
    setState(current => ({ ...current, runs: current.runs.map(item => item.id === id ? next : item) }));
    if (proceed) scheduleRun(next);
  }
  function resumeRun(id: string) {
    const run = state.runs.find(run => run.id === id); if (!run) return;
    const resumed = { ...run, state: "running" as const, activity: "Working on your task" };
    setState(current => ({ ...current, runs: current.runs.map(item => item.id === id ? resumed : item) })); scheduleRun(resumed);
  }
  function openRun(id: string) {
    const run = state.runs.find(run => run.id === id); if (!run) return;
    const windowId = addComposer(run.conversationId);
    if (run.branchId) handles.current.get(windowId)?.selectBranch(run.branchId);
  }
  function reset() {
    timers.current.forEach(clearTimeout); timers.current.clear(); replies.current.clear();
    sequence.current = 1; layers.current = 1; setState(current => ({ ...initialState(), ...initialOverrides, generation: current.generation + 1 }));
  }
  return { state, patch, allCommands, conversations, activeWindow, register, updateWindow, closeMenus, focusWindow, addComposer, hideWindow, dismissFrontComposer, startRun, stopRun, resumeRun, resolveAttention, openRun, reset };
}

export type DemoWorkspace = ReturnType<typeof useDemoWorkspace>;
