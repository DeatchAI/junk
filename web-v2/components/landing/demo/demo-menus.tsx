import { useRef, useState } from "react";
import { agents, type DemoFile } from "./demo-data";
import { AgentLogo, Icon } from "./demo-icons";
import type { DemoController } from "./use-demo";
import type { DemoWorkspace } from "./demo-workspace";
import { MenuRow, MenuSurface, NestedMenuRow } from "./demo-menu-controls";
import s from "./demo-panels.module.css";
import edge from "./demo-edge-notch.module.css";

export function AgentMenu({ demo }: { demo: DemoController }) {
  const [submenu, setSubmenu] = useState<string | null>(null);
  const selected = agents.find(agent => agent.id === demo.state.agent)!;
  return <MenuSurface className={`${s.menu} ${s.agentMenu}`} role="dialog" aria-label="Agent and model settings" data-demo-menu="">
    <NestedMenuRow label="Agent" value={selected.name} onOpen={() => setSubmenu("agent")}>
      {submenu === "agent" && <MenuSurface placement="right" className={`${s.menu} ${s.submenu}`} aria-label="Choose agent">
        {agents.map(agent => <button type="button" className={s.menuRow} key={agent.id} onClick={() => { demo.selectAgent(agent.id); setSubmenu(null); }}>
          <AgentLogo agent={agent.id}/><span>{agent.name}</span><span className={s.rowValue}/>{demo.state.agent === agent.id && <Icon name="check" size={12}/>}
        </button>)}
      </MenuSurface>}
    </NestedMenuRow>
    <NestedMenuRow label="Model" value={demo.state.model} onOpen={() => setSubmenu("model")}>
      {submenu === "model" && <MenuSurface placement="right" className={`${s.menu} ${s.submenu}`} aria-label="Choose model">
        {selected.models.map(model => <MenuRow key={model} label={model} checked={model === demo.state.model}
          onClick={() => { demo.patch({ model }); setSubmenu(null); }}/>) }
      </MenuSurface>}
    </NestedMenuRow>
    <NestedMenuRow label="Effort" value={demo.state.effort} onOpen={() => setSubmenu("effort")}>
      {submenu === "effort" && <MenuSurface placement="right" className={`${s.menu} ${s.submenu}`} aria-label="Choose effort">
        {["Auto", "Low", "Medium", "High"].map(effort => <MenuRow key={effort} label={effort} checked={demo.state.effort === effort}
          onClick={() => { demo.patch({ effort }); setSubmenu(null); }}/>) }
      </MenuSurface>}
    </NestedMenuRow>
    <hr/>
    <NestedMenuRow label="Permissions" value={demo.state.permission} onOpen={() => setSubmenu("permissions")}>
      {submenu === "permissions" && <MenuSurface placement="right" className={`${s.menu} ${s.submenu}`} aria-label="Choose permissions">
        {["Agent default", "Ask before changes", "Approve for me"].map(permission => <MenuRow key={permission} label={permission}
          checked={permission === demo.state.permission} onClick={() => { demo.patch({ permission }); setSubmenu(null); }}/>) }
      </MenuSurface>}
    </NestedMenuRow>
    <NestedMenuRow label="Context" value="Last message" onOpen={() => setSubmenu("context")}>
      {submenu === "context" && <MenuSurface placement="right" className={`${s.menu} ${s.submenu} ${s.contextPanel}`}>
        <span>Last message</span><p>{demo.branch.messages.at(-1)?.prompt ?? "Your next task starts here."}</p>
        <div><span>Project</span><strong>{demo.state.project || "No project"}</strong></div>
        <div><span>Attachments</span><strong>{demo.branch.draft.files.length}</strong></div>
      </MenuSurface>}
    </NestedMenuRow>
    <button type="button" className={`${s.menuRow} ${s.mutedRow}`} onClick={() => { demo.patch({ effort: "Auto", permission: "Agent default" }); setSubmenu(null); }}>
      <Icon name="reset" size={13}/><span>Reset to default</span>
    </button>
  </MenuSurface>;
}

export function ProjectMenu({ demo }: { demo: DemoController }) {
  const [query, setQuery] = useState("");
  const [adding, setAdding] = useState(false);
  const input = useRef<HTMLInputElement>(null);
  function addProject() {
    const project = query.trim();
    if (!project) { input.current?.focus(); return; }
    demo.patch({ projects: [...new Set([...demo.state.projects, project])], project, menu: null });
  }
  return <MenuSurface className={`${s.menu} ${s.projectMenu}`} role="dialog" aria-label="Choose project" data-demo-menu="">
    <label className={s.search}><Icon name="search" size={14}/><input ref={input} autoFocus value={query} onChange={event => setQuery(event.target.value)}
      placeholder={adding ? "Project name" : "Search projects"} aria-label={adding ? "New project name" : "Search projects"}
      onKeyDown={event => { if (event.key === "Enter" && adding) addProject(); }}/></label>
    <hr/>
    {adding ? <MenuRow label="Add project" icon="folderPlus" onClick={addProject}/> : <MenuRow label="New project" icon="folderPlus" onClick={() => { setAdding(true); setQuery(""); input.current?.focus(); }}/>} 
    <div className={s.projectList}>
      {demo.state.projects.filter(project => project.toLowerCase().includes(query.toLowerCase()) || adding).map(project =>
        <MenuRow key={project} label={project} icon="folder" checked={demo.state.project === project} onClick={() => demo.patch({ project, menu: null })}/>)}
      {!adding && !demo.state.projects.some(project => project.toLowerCase().includes(query.toLowerCase())) && <p className={s.empty}>No projects found</p>}
    </div>
    <hr/>
    <MenuRow label="Don’t work in a project" icon="close" checked={!demo.state.project} onClick={() => demo.patch({ project: "", menu: null })}/>
  </MenuSurface>;
}

export function HistoryPanel({ workspace }: { workspace: DemoWorkspace }) {
  const [query, setQuery] = useState("");
  const items = workspace.conversations.filter(item => `${item.title} ${item.project}`.toLowerCase().includes(query.toLowerCase()));
  return <aside className={`${s.history} ${edge.edge} -translate-y-1/2 origin-left scale-80`} aria-label="Conversation history" data-open={workspace.state.historyOpen} data-notch-edge="left"
    aria-hidden={!workspace.state.historyOpen} inert={!workspace.state.historyOpen} data-demo-menu="" data-history-panel="">
    <label className={s.historySearch}><Icon name="search"/><input placeholder="Search" aria-label="Search conversation history" value={query} onChange={event => setQuery(event.target.value)}/></label>
    <div className={s.historyList}>
      {[...new Set(items.map(item => item.project))].map(project => <div className={s.historyGroup} key={project}>
        <p><Icon name="folder" size={15}/>{project}</p>
        {items.filter(item => item.project === project).map(item => <button type="button" key={item.id} aria-pressed={workspace.activeWindow?.conversationId === item.id} onClick={() => workspace.addComposer(item.id)}>
          <AgentLogo agent={item.agent} size={14}/><span>{item.title}</span>
        </button>)}
      </div>)}
      {!items.length && <p className={s.empty}>No conversations found</p>}
    </div>
  </aside>;
}

export function FilePreview({ file, onClose }: { file: DemoFile; onClose: () => void }) {
  return <div className={s.previewBackdrop} onClick={onClose}>
    <div role="dialog" aria-label={`Preview ${file.name}`} className={s.filePreview} onClick={event => event.stopPropagation()}>
      <header><span>{file.name}</span><button type="button" autoFocus aria-label="Close attachment preview" onClick={onClose}><Icon name="close"/></button></header>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      {file.kind === "image" ? <img src={file.src} alt="Acme design reference. Make room for what matters."/> : file.kind === "chat" || file.kind === "context"
        ? <div className={s.previewText}><p>{file.name}</p><p>{file.description ?? "This context is attached to your message."}</p><span>{file.path}</span></div>
        : <pre>{file.name.endsWith("tsx") ? "export default function Page() {\n  return (\n    <main className=\"page\">\n      <h1>Make room for what matters.</h1>\n      <ProjectGrid />\n    </main>\n  );\n}" : file.name.endsWith("css") ? ".page {\n  max-width: 1080px;\n  margin-inline: auto;\n  padding: 64px 32px;\n}" : "# Design brief\n\nA quieter layout.\nMore space around the images.\nKeep the existing typography."}</pre>}
    </div>
  </div>;
}
