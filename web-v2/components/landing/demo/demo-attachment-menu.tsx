import { useEffect, useMemo, useState } from "react";
import { sampleFiles, type DemoFile } from "./demo-data";
import { Icon, type IconName } from "./demo-icons";
import { MenuRow, MenuSurface, NestedMenuRow } from "./demo-menu-controls";
import type { DemoController } from "./use-demo";
import s from "./demo-panels.module.css";

const categories: { id: string; label: string; icon: IconName }[] = [
  { id: "files", label: "Files & Folders", icon: "files" },
  { id: "tabs", label: "Tabs", icon: "tabs" },
  { id: "chats", label: "Past conversations", icon: "chats" },
  { id: "installed", label: "Installed Skills", icon: "sparkles" },
  { id: "discover", label: "Discover Skills", icon: "search" },
  { id: "mcp", label: "Connected MCP Servers", icon: "server" },
];
const capabilities: DemoFile[] = [
  { id: "browser", name: "Browser", kind: "context", icon: "globe", path: "Capability", description: "Browser context is included with this sample message." },
  { id: "macos", name: "macOS", kind: "context", icon: "window", path: "Capability", description: "macOS context is included with this sample message." },
  { id: "secrets", name: "Secrets", kind: "context", icon: "lock", path: "Capability", description: "The native app uses Touch ID when a task needs a saved credential." },
];
const skills: DemoFile[] = [
  { id: "skill-design", name: "Frontend design", kind: "context", icon: "sparkles", path: "Installed skill", description: "Guidance for refining interface layout and typography." },
  { id: "skill-review", name: "Code review", kind: "context", icon: "sparkles", path: "Installed skill", description: "Review changes for bugs, risks, and missing tests." },
];

export function AttachmentMenu({ demo }: { demo: DemoController }) {
  const typedQuery = demo.state.trigger?.kind === "attachments" ? demo.state.trigger.query : "";
  const [active, setActive] = useState<string | null>(demo.state.attachmentSection);
  const [search, setSearch] = useState<string | null>(null);
  const [rootIndex, setRootIndex] = useState(0);
  const [childIndex, setChildIndex] = useState(0);
  const category = active ?? (typedQuery ? "files" : null);
  const query = (search ?? typedQuery).toLowerCase();
  const collections = useMemo<Record<string, DemoFile[]>>(() => ({
    files: [...sampleFiles.filter(file => file.kind !== "chat"), { id: `folder-${demo.state.project}`, name: demo.state.project || "Project", kind: "context", icon: "files", path: "Folder" }],
    tabs: [
      { id: "tab-figma", name: "Design reference — Figma", kind: "context", icon: "tabs", path: "Browser tab" },
      { id: "tab-github", name: "Pull request — GitHub", kind: "context", icon: "tabs", path: "Browser tab" },
    ],
    chats: demo.conversations.map(item => ({ id: `chat-${item.id}`, name: item.title, kind: "chat", icon: "chats", path: item.project, description: "Past conversation attached as context for this message." })),
    installed: skills,
    discover: [...skills, { id: "skill-browser", name: "Browser testing", kind: "context", icon: "sparkles", path: "Discover skill" }],
    mcp: demo.state.mcpServers,
  }), [demo.conversations, demo.state.mcpServers, demo.state.project]);
  const results = (collections[category ?? "files"] ?? []).filter(file => `${file.name} ${file.path}`.toLowerCase().includes(query));

  useEffect(() => {
    function navigate(event: KeyboardEvent) {
      if (event.altKey || event.metaKey || event.ctrlKey || !["ArrowUp", "ArrowDown", "ArrowRight", "ArrowLeft", "Enter"].includes(event.key)) return;
      if ((event.target as HTMLElement)?.tagName === "INPUT" && ["ArrowRight", "ArrowLeft"].includes(event.key)) return;
      event.preventDefault(); event.stopPropagation();
      if (category) {
        if (event.key === "ArrowLeft") { setActive(null); setSearch(""); return; }
        if (event.key === "Enter") { const item = results[Math.min(childIndex, results.length - 1)]; if (item) demo.attach(item); return; }
        if (event.key === "ArrowDown" || event.key === "ArrowUp") setChildIndex(current => (current + (event.key === "ArrowDown" ? 1 : -1) + Math.max(1, results.length)) % Math.max(1, results.length));
      } else if (event.key === "Enter" || event.key === "ArrowRight") {
        if (rootIndex < categories.length) setActive(categories[rootIndex].id);
        else demo.toggleContext(capabilities[rootIndex - categories.length]);
      } else setRootIndex(current => (current + (event.key === "ArrowDown" ? 1 : -1) + 9) % 9);
    }
    document.addEventListener("keydown", navigate, true);
    return () => document.removeEventListener("keydown", navigate, true);
  }, [category, childIndex, demo, results, rootIndex]);

  function open(id: string, index: number) { setActive(id); setRootIndex(index); setSearch(null); setChildIndex(0); }
  return <MenuSurface placement="below" className={`${s.menu} ${s.attachmentMenu}`} role="dialog" aria-label="Attachments" data-demo-menu="">
    {categories.map((item, index) => <NestedMenuRow key={item.id} label={item.label} icon={item.icon}
      active={category === item.id || (!category && rootIndex === index)} onOpen={() => open(item.id, index)}>
      {category === item.id && <MenuSurface placement="right" className={`${s.menu} ${s.submenu} ${s.categorySubmenu}`} role="group" aria-label={item.label}>
        <label className={s.search}><Icon name="search" size={13}/><input aria-label={`Search ${item.label}`} placeholder={`Search ${item.label.toLowerCase()}`} value={search ?? typedQuery} onChange={event => { setSearch(event.target.value); setChildIndex(0); }}/></label>
        <hr/><div className={s.attachmentResults}>
          {results.map((file, index) => <button type="button" key={file.id} className={s.contextRow} data-active={index === childIndex}
            onMouseEnter={() => setChildIndex(index)} onClick={() => demo.attach(file)}>
            <Icon name={file.icon ?? (file.kind === "chat" ? "chats" : "file")} size={15}/><span>{file.name}<small>{file.path}</small></span>
            {demo.branch.draft.files.some(value => value.id === file.id) && <Icon name="check" size={11}/>}
          </button>)}
          {!results.length && <p className={s.empty}>No matches found</p>}
        </div>
      </MenuSurface>}
    </NestedMenuRow>)}
    {capabilities.map((file, index) => <MenuRow key={file.id} label={file.name} icon={file.icon} active={!category && rootIndex === index + categories.length}
      checked={demo.branch.draft.files.some(value => value.id === file.id)} onMouseEnter={() => { setActive(null); setRootIndex(index + categories.length); }} onClick={() => demo.toggleContext(file)}/>)}
  </MenuSurface>;
}
