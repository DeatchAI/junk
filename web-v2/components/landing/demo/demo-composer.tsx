import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { AgentLogo, Icon, IconButton } from "./demo-icons";
import { AgentMenu, ProjectMenu } from "./demo-menus";
import { AttachmentMenu } from "./demo-attachment-menu";
import { CommandMenu } from "./demo-command-menu";
import { DraftEditor } from "./demo-draft-editor";
import { DemoTranscript } from "./demo-transcript";
import { DemoAttention } from "./demo-attention";
import { agents, type DemoFile, type DemoMessage, type DemoRun } from "./demo-data";
import type { DemoController } from "./use-demo";
import type { DemoWorkspace } from "./demo-workspace";
import { composerClasses as c } from "./demo-classes";
import p from "./demo-panels.module.css";
import edge from "./demo-edge-notch.module.css";

export function Attachments({ files, onPreview, onRemove }: { files: DemoFile[]; onPreview: (file: DemoFile) => void; onRemove?: (id: string) => void }) {
  return <div className={p.attachments}>
    {files.filter(file => file.kind === "image").map(file => <span className={p.thumbnail} key={file.id}>
      <button type="button" aria-label={`Preview ${file.name}`} onClick={() => onPreview(file)}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={file.src} width={52} height={52} alt="Acme layout reference" draggable={false}/>
      </button>
      {onRemove && <button type="button" className={p.removeMedia} aria-label={`Remove ${file.name}`} onClick={() => onRemove(file.id)}><Icon name="close" size={9}/></button>}
    </span>)}
  </div>;
}

export function FilePill({ file, onPreview }: { file: DemoFile; onPreview: (file: DemoFile) => void }) {
  return <span className={p.filePill}>
    <button type="button" onClick={() => onPreview(file)} aria-label={`Preview ${file.name}`}><Icon name={file.icon ?? (file.kind === "chat" ? "chat" : "file")} size={12}/>{file.name}</button>
  </span>;
}

function FollowUps({ demo }: { demo: DemoController }) {
  const [preview, setPreview] = useState<{ index: number; x: number } | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const strip = useRef<HTMLDivElement>(null);
  const message = preview && demo.branch.messages[preview.index];
  function show(index: number, button: HTMLButtonElement, immediately = false) {
    if (timer.current) clearTimeout(timer.current);
    const parent = strip.current!.getBoundingClientRect();
    const x = Math.max(0, Math.min(button.getBoundingClientRect().left - parent.left, parent.width - Math.min(370, parent.width)));
    if (immediately) setPreview({ index, x });
    else timer.current = setTimeout(() => setPreview({ index, x }), 240);
  }
  function dismiss(preserveFocus = false) {
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => {
      if (!preserveFocus || !strip.current?.contains(document.activeElement)) setPreview(null);
    }, 180);
  }
  return <div className={c.followUps} ref={strip} onMouseLeave={() => dismiss(true)}
    onBlur={event => { if (!event.currentTarget.contains(event.relatedTarget)) dismiss(); }}>
    <div className={c.followUpNumbers} aria-label="Follow-up messages">
      {demo.branch.messages.map((message, index) => <button type="button" key={message.id}
        className={c.followUpButton}
        aria-label={`Show response to message ${index + 1}`} aria-pressed={demo.branch.selected === index}
        onClick={() => demo.selectMessage(index)} onMouseEnter={event => show(index, event.currentTarget)}
        onFocus={event => show(index, event.currentTarget, true)}>
        {index + 1}
      </button>)}
    </div>
    {message && preview && <div className={p.messagePreview} style={{ left: preview.x }} role="dialog" aria-label={`Message ${preview.index + 1}`}
      onMouseEnter={() => { if (timer.current) clearTimeout(timer.current); }} onMouseLeave={() => dismiss(true)}>
      <header><span>Message {preview.index + 1}</span><IconButton icon="edit" label={`Edit message ${preview.index + 1}`} size={12}
        disabled={!!demo.state.run} onClick={() => { setPreview(null); demo.edit(preview.index); }}/></header>
      <div className={p.messageContent}>
        {!!message.files.length && <div className={p.sentFiles}>
          <Attachments files={message.files} onPreview={file => demo.patch({ previewFile: file })}/>
          <div>{message.files.filter(file => file.kind !== "image").map(file => <FilePill file={file} key={file.id} onPreview={file => demo.patch({ previewFile: file })}/>)}</div>
        </div>}
        {!!message.commands?.length && <div className={p.sentCommands}>{message.commands.map(command => <span key={command.id}>/{command.command}</span>)}</div>}
        <p>{message.prompt}</p>
      </div>
    </div>}
  </div>;
}

function Response({ message, demo, compact = false }: { message: DemoMessage; demo: DemoController; compact?: boolean }) {
  const [copied, setCopied] = useState(false);
  const running = demo.state.run?.messageId === message.id;
  async function copy() {
    try { await navigator.clipboard.writeText(message.answer); setCopied(true); } catch { setCopied(false); }
  }
  return <div className={compact ? c.responseCompact : c.response}>
    {running && <div className={c.activitySummary}><span className={c.spinner}/><span>{demo.state.activity}</span></div>}
    {message.transcript && !running ? <DemoTranscript parts={message.transcript}/> :
      <p className={c.responseBody} data-no-drag="">{message.answer || (running ? "Working…" : demo.state.phase === "stopped" ? "The task was stopped. You can continue whenever you’re ready." : "Task complete. You can continue the conversation here.")}</p>}
    {!running && !!message.answer && <button type="button" className={c.copyButton} onClick={copy}><Icon name={copied ? "check" : "copy"} size={13}/>{copied ? "Copied" : "Copy"}</button>}
  </div>;
}

export function Composer({ demo }: { demo: DemoController }) {
  const editor = useRef<HTMLDivElement>(null);
  const caretMenu = useRef<HTMLDivElement>(null);
  const selected = demo.branch.messages[demo.branch.selected] ?? demo.branch.messages.at(-1);
  const currentBranch = demo.state.branches.findIndex(branch => branch.id === demo.state.branchId);
  const hasMedia = demo.branch.draft.files.some(file => file.kind === "image");

  useLayoutEffect(() => {
    if (!editor.current || !caretMenu.current || !["attachments", "commands"].includes(demo.state.menu ?? "")) return;
    const input = editor.current;
    const selection = document.getSelection();
    const range = selection?.rangeCount && input.contains(selection.anchorNode) ? selection.getRangeAt(0).getBoundingClientRect() : null;
    const anchor = range?.height ? range : input.getBoundingClientRect();
    const composer = caretMenu.current.offsetParent?.getBoundingClientRect(); if (!composer) return;
    caretMenu.current.style.left = `${Math.max(14, anchor.left - composer.left)}px`;
    caretMenu.current.style.top = `${anchor.bottom - composer.top + 4}px`;
  }, [demo.branch.draft.text, demo.state.editorSelection, demo.state.menu, hasMedia]);

  return <>
    {!!demo.branch.messages.length && <FollowUps key={demo.state.branchId} demo={demo}/>}
    {demo.state.expanded && !demo.state.revision ? <div className={c.expandedHistory}>
      {demo.branch.messages.map(message => <div key={message.id}><p className={c.expandedPrompt}>{message.prompt}</p><Response message={message} demo={demo} compact/></div>)}
      {!demo.branch.messages.length && <p className={c.expandedEmpty}>A little more room for the conversation.</p>}
    </div> : selected && !demo.state.revision ? <Response key={selected.id} message={selected} demo={demo}/> : null}
    <div className={c.composer}>
      <div className={c.dragHandle} title="Drag composer" aria-hidden="true"/>
      {demo.state.revision && <div className={c.revision}><span><Icon name="edit" size={10}/>Editing message {demo.state.revision.index + 1}</span><button type="button" onClick={demo.cancelEdit}>Cancel</button></div>}
      <div className={c.windowControls}>
        <IconButton icon={demo.state.expanded ? "shrink" : "expand"} label={demo.state.expanded ? "Shrink composer" : "Expand composer"}
          className={c.controlButton} onClick={() => demo.patch({ expanded: !demo.state.expanded, menu: null })}/>
        <IconButton icon="close" label="Close composer" className={c.controlButton} onClick={() => demo.patch({ composerOpen: false, menu: null, islandOpen: true })}/>
      </div>
      {hasMedia && <div className={c.draftMedia}><Attachments files={demo.branch.draft.files} onPreview={file => demo.patch({ previewFile: file })} onRemove={demo.removeFile}/></div>}
      <div className={c.editorLine} data-has-media={hasMedia} onClick={event => {
        if (event.target instanceof Element && !event.target.closest('button, input, textarea, [data-demo-menu]')) editor.current?.focus();
      }}>
        <DraftEditor demo={demo} editorRef={editor}/>
      </div>
      <div ref={caretMenu} className={c.caretMenuAnchor}>
        {demo.state.menu === "attachments" && <AttachmentMenu demo={demo}/>}
        {demo.state.menu === "commands" && <CommandMenu demo={demo}/>}
      </div>
      <div className={c.toolbar}>
        <div className={c.agentControls}>
          <div className={c.menuAnchor}>
            <IconButton icon="brain" size={15} label="Agent and model" className={c.controlButton} aria-expanded={demo.state.menu === "agent"} data-menu-trigger=""
              onClick={() => demo.patch({ menu: demo.state.menu === "agent" ? null : "agent" })}/>
            {demo.state.menu === "agent" && <AgentMenu demo={demo}/>}
          </div>
          {demo.state.branches.length > 1 && <div className={c.branchSwitcher} aria-label="Conversation branches">
            <IconButton icon="left" size={10} label="Previous branch" className={c.controlButton} disabled={currentBranch === 0 || !!demo.state.run}
              onClick={() => demo.switchBranch(demo.state.branches[currentBranch - 1].id)}/>
            <span title={demo.branch.label}>{currentBranch + 1} / {demo.state.branches.length}</span>
            <IconButton icon="right" size={10} label="Next branch" className={c.controlButton} disabled={currentBranch === demo.state.branches.length - 1 || !!demo.state.run}
              onClick={() => demo.switchBranch(demo.state.branches[currentBranch + 1].id)}/>
          </div>}
        </div>
        <div className={c.toolbarRight}>
          <div className={c.menuAnchor}>
            <IconButton icon="attach" label="Attach files or past conversations" size={15} className={c.toolbarRightButton} data-menu-trigger="" aria-expanded={demo.state.menu === "attachments"}
              onClick={() => demo.patch({ menu: demo.state.menu === "attachments" ? null : "attachments" })}/>
          </div>
          <IconButton icon="history" label="Conversation history" className={c.toolbarRightButton} data-history-trigger="" onClick={() => demo.patch({ historyOpen: !demo.state.historyOpen, menu: null })}/>
          <IconButton icon="newChat" label="New chat" className={c.toolbarRightButton} onClick={demo.newChat}/>
          <IconButton className={c.sendButton} data-send-button="" icon={demo.state.run ? "stop" : "up"} size={18}
            label={demo.state.run ? "Stop task" : demo.state.revision ? "Send edited message in a new branch" : "Send message"}
            disabled={!demo.state.run && !demo.branch.draft.text.trim() && !demo.branch.draft.files.length && !demo.branch.draft.commands.length} onClick={demo.state.run ? demo.stop : demo.send}/>
        </div>
      </div>
    </div>
    <div className={c.projectBar}>
      <div className={c.menuAnchor}>
        <button type="button" data-menu-trigger="" className={c.projectButton} aria-label={`Choose project: ${demo.state.project || "none"}`}
          aria-expanded={demo.state.menu === "project"} onClick={() => demo.patch({ menu: demo.state.menu === "project" ? null : "project" })}>
          <Icon name="folder" size={16}/><span>{demo.state.project || "Projects"}</span><Icon name="down" size={10}/>
        </button>
        {demo.state.menu === "project" && <ProjectMenu demo={demo}/>}
      </div>
    </div>
  </>;
}

function RunStatus({ run }: { run: DemoRun }) {
  return <>{run.state === "running" ? <span className={c.spinner}/> :
    <Icon name={run.state === "approval" ? "shield" : run.state === "question" ? "chat" : run.state === "stopped" ? "stop" : "check"} size={10}/>}
    <span className="max-w-[152px] overflow-hidden text-ellipsis whitespace-nowrap max-[600px]:max-w-[130px]">{run.activity}</span></>;
}

export function ActivityIsland({ workspace }: { workspace: DemoWorkspace }) {
  const collapseTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const content = useRef<HTMLDivElement>(null);
  const [selectedId, setSelectedId] = useState(() => workspace.state.runs.find(run => run.state === "approval" || run.state === "question")?.id ?? null);
  const primary = workspace.state.runs.find(run => run.state === "running") ?? workspace.state.runs[0];
  const selected = workspace.state.runs.find(run => run.id === selectedId && (run.state === "approval" || run.state === "question"));
  useEffect(() => () => { if (collapseTimer.current) clearTimeout(collapseTimer.current); }, []);
  useLayoutEffect(() => { if (selectedId && content.current) content.current.scrollTop = 0; }, [selectedId]);
  function keepOpen() { if (collapseTimer.current) clearTimeout(collapseTimer.current); }
  function expand() { keepOpen(); workspace.patch({ islandOpen: true }); }
  return <aside className={`${c.island} ${edge.edge} ${workspace.state.islandOpen ? c.islandExpanded : ""}`} aria-label="Activity island" data-activity-island="" data-notch-edge="right" data-expanded={workspace.state.islandOpen}
    onMouseEnter={expand} onMouseLeave={event => { if (!event.currentTarget.contains(document.activeElement)) collapseTimer.current = setTimeout(() => workspace.patch({ islandOpen: false }), 400); }}>
    {!workspace.state.islandOpen ? <button type="button" className={c.islandCollapsed} aria-label="Show detached tasks" onClick={() => workspace.patch({ islandOpen: true })}>
      <AgentLogo agent={primary.agent} size={20}/><span>{workspace.state.runs.length}</span>
    </button> : <div ref={content} className={selected ? "max-h-[var(--attention-max-height,calc(100svh_-_180px))] overflow-y-auto [scrollbar-width:thin]" : ""}>
      {selected && <DemoAttention key={selected.id} run={selected} onResolve={proceed => workspace.resolveAttention(selected.id, proceed)}/>}
      <div className={c.taskList}>{workspace.state.runs.map(run => <div className={`${c.taskRow} ${selected?.id === run.id ? "rounded-xl [background-color:var(--app-control)]" : ""}`} key={run.id}>
        <button type="button" className={c.taskLabel} aria-label={`Open ${run.title}`}
          aria-expanded={run.attention && (run.state === "approval" || run.state === "question") ? selected?.id === run.id : undefined}
          onClick={() => run.state === "approval" || run.state === "question" ? setSelectedId(current => current === run.id ? null : run.id) : workspace.openRun(run.id)}>
          <AgentLogo agent={run.agent}/><span><strong>{run.title}</strong><small>{agents.find(agent => agent.id === run.agent)!.name}<b>·</b>
            {run.project ? <span>{run.project}</span> : <RunStatus run={run}/>}</small>
            {run.project && <small><RunStatus run={run}/></small>}</span>
        </button>
        {run.state === "running" || run.state === "approval" || run.state === "question" ? <IconButton icon="stop" label={`Stop ${run.title}`} size={12} className={c.taskActionButton} onClick={() => workspace.stopRun(run.id)}/>
          : run.state === "stopped" ? <IconButton icon="play" label={`Resume ${run.title}`} size={12} className={c.taskActionButton} onClick={() => workspace.resumeRun(run.id)}/> : null}
        <IconButton icon="external" label={`Jump to ${run.title}`} size={12} className={c.taskActionButton} onClick={() => workspace.openRun(run.id)}/>
      </div>)}</div>
    </div>}
  </aside>;
}
