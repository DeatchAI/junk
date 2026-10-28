import { useEffect, useMemo, useRef, useState } from "react";
import { Icon } from "./demo-icons";
import { MenuRow, MenuSurface } from "./demo-menu-controls";
import type { DemoCommand } from "./demo-data";
import type { DemoController } from "./use-demo";
import s from "./demo-panels.module.css";

type CreateMode = "command" | "workflow" | "mcp";

export function CommandMenu({ demo }: { demo: DemoController }) {
  const [selected, setSelected] = useState(0);
  const [creating, setCreating] = useState<CreateMode | null>(null);
  const [name, setName] = useState("");
  const [prompt, setPrompt] = useState("");
  const query = demo.state.trigger?.kind === "commands" ? demo.state.trigger.query.toLowerCase() : "";
  const { workflows, commands, items } = useMemo(() => {
    const matches = (command: DemoCommand) => `${command.command} ${command.title}`.toLowerCase().includes(query);
    const workflows = demo.allCommands.filter(command => command.kind === "workflow" && matches(command));
    const commands = demo.allCommands.filter(command => command.kind !== "workflow" && matches(command));
    return { workflows, commands, items: [...workflows, ...commands] };
  }, [demo.allCommands, query]);
  const selectedIndex = Math.min(selected, Math.max(0, items.length - 1));
  const list = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (creating) return;
    function navigate(event: KeyboardEvent) {
      if (event.altKey || event.ctrlKey || event.metaKey || !["ArrowDown", "ArrowUp", "Enter"].includes(event.key) || !items.length) return;
      if (event.key === "Enter" && event.target instanceof HTMLElement && event.target.closest('button:not([role="option"])')) return;
      event.preventDefault(); event.stopPropagation();
      if (event.key === "Enter") demo.attachCommand(items[selectedIndex]);
      else {
        const next = (selectedIndex + (event.key === "ArrowDown" ? 1 : -1) + items.length) % items.length;
        setSelected(next); list.current?.querySelectorAll<HTMLElement>('[role="option"]')[next]?.scrollIntoView({ block: "nearest" });
      }
    }
    document.addEventListener("keydown", navigate, true);
    return () => document.removeEventListener("keydown", navigate, true);
  }, [creating, demo, items, selectedIndex]);

  function create() {
    const label = name.trim(); if (!label || !prompt.trim()) return;
    if (creating === "mcp") {
      const server = { id: `mcp-${label.toLowerCase().replace(/\s+/g, "-")}`, name: label, kind: "context" as const, icon: "server" as const,
        path: "Connected MCP server", description: prompt.trim() };
      demo.patch({ mcpServers: [...demo.state.mcpServers.filter(item => item.id !== server.id), server], menu: "attachments", attachmentSection: "mcp" });
    } else {
      const command = label.replace(/^\//, "").replace(/\s+/g, "-").toLowerCase();
      demo.createCommand({ id: `custom-${command}`, command, title: label, subtitle: prompt.trim(), icon: "bolt", kind: creating ?? "command" });
    }
  }
  function section(title: string, values: DemoCommand[], offset: number) {
    if (!values.length) return null;
    return <div><p className={s.menuHeading}>{title}</p>{values.map((command, index) => <button type="button" className={s.commandRow}
      key={command.id} role="option" title={command.subtitle} aria-selected={offset + index === selectedIndex}
      onFocus={() => setSelected(offset + index)} onMouseEnter={() => setSelected(offset + index)} onClick={() => demo.attachCommand(command)}>
      <Icon name={command.icon} size={16}/><span>{command.title}</span>
    </button>)}</div>;
  }
  const title = creating === "workflow" ? "Create Workflow" : creating === "mcp" ? "Connect MCP" : "New Command";
  return <MenuSurface placement="below" className={`${s.menu} ${s.commandMenu}`} role="dialog" aria-label="Commands and workflows" data-demo-menu="">
    {creating ? <div className={s.createCommand}>
      <header><button type="button" aria-label="Back to commands" onClick={() => setCreating(null)}><Icon name="left" size={12}/></button><span>{title}</span></header>
      <input autoFocus aria-label={creating === "mcp" ? "MCP server name" : `${creating === "workflow" ? "Workflow" : "Command"} name`}
        placeholder={creating === "mcp" ? "Server name" : "Name"} value={name} onChange={event => setName(event.target.value)}/>
      {creating === "mcp" ? <input aria-label="MCP server URL" placeholder="https://…" value={prompt} onChange={event => setPrompt(event.target.value)}/>
        : <textarea aria-label="Command instructions" placeholder="What should it do?" value={prompt} onChange={event => setPrompt(event.target.value)}/>}
      <button type="button" disabled={!name.trim() || !prompt.trim()} onClick={create}>{title}</button>
    </div> : <>
      <div className={s.commandList} ref={list} role="listbox" aria-label="Available commands">
        {section("Workflows", workflows, 0)}{section("Commands", commands, workflows.length)}
        {!items.length && <p className={s.empty}>No matching commands</p>}
      </div>
      <p className={s.menuHeading}>Create</p>
      <MenuRow label="New Command" icon="plus" onClick={() => setCreating("command")}/>
      <MenuRow label="Create Workflow" icon="workflow" onClick={() => setCreating("workflow")}/>
      <MenuRow label="Connect MCP" icon="server" onClick={() => setCreating("mcp")}/>
    </>}
  </MenuSurface>;
}
