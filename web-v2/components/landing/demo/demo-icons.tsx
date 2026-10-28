import type { ButtonHTMLAttributes } from "react";

const brainHalf = "M12 5.2C12 3.6 10.8 2.5 9.3 2.5C7.7 2.5 6.4 3.8 6.4 5.35C4.45 5.3 3 6.8 3 8.65C3 9.4 3.25 10.1 3.7 10.65C2.8 11.3 2.25 12.45 2.25 13.65C2.25 15.4 3.55 16.9 5.25 17.15C5.25 19.5 6.75 21.3 9.1 21.3C10.75 21.3 12 20.15 12 18.5M6.4 5.35C6.4 6.7 7.1 7.6 8.2 8.1M3.7 10.65C4.8 10.2 6.1 10.5 6.8 11.15M5.25 17.15C6.6 17.1 7.75 16.2 7.85 14.8M9.2 12C10.7 12 12 10.6 12 9.2";
export const iconPaths = {
  folder: "M19.5 20h-15Q3 20 3 18.5v-13Q3 4 4.5 4h4Q9.4 4 10 4.7l1.7 1.8h7.8Q21 6.5 21 8v10.5Q21 20 19.5 20ZM3 10h18",
  folderPlus: "M11 20H4.5Q3 20 3 18.5v-13Q3 4 4.5 4h4Q9.4 4 10 4.7l1.7 1.8h7.8Q21 6.5 21 8v3.5M3 10h18m-2.5 4.5v8m-4-4h8",
  search: "m16.5 16.5 4 4M18 10.5a7.5 7.5 0 1 1-15 0 7.5 7.5 0 0 1 15 0Z",
  close: "m6 6 12 12M18 6 6 18",
  expand: "M4 10V4h6M14 20h6v-6M4 4l7 7m2 2 7 7",
  shrink: "M10 4v6H4m16 4h-6v6M4 4l6 6m4 4 6 6",
  history: "M3 10a9 9 0 1 1 1.5 7M3 4v6h6m3-4v6l3 2",
  newChat: "M5 4h14a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2h-7l-5 3v-3H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2Zm7 4v7m-3.5-3.5h7",
  up: "M12 19V5m-6 6 6-6 6 6",
  right: "m9 5 7 7-7 7",
  left: "m15 5-7 7 7 7",
  down: "m6 9 6 6 6-6",
  check: "m5 12 4 4L19 6",
  file: "M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9Zm0 0v6h6M8 13h8m-8 4h8",
  chat: "M21 11.5a8.5 8.5 0 0 1-8.5 8.5H6l-4 2 1.8-5A8.5 8.5 0 1 1 21 11.5Z",
  copy: "M9 5H6a2 2 0 0 0-2 2v13h11v-3M9 2h6l5 5v10H9Zm6 0v5h5",
  edit: "m4 16 12-12 4 4L8 20l-5 1 1-5ZM14 6l4 4",
  attach: "m9 15 7-7a3 3 0 0 1 4 4L10 22a5 5 0 0 1-7-7L14 4a2 2 0 0 1 3 3L7 17",
  reset: "M4 10a8 8 0 1 1 .6 6M4 4v6h6",
  external: "M6 18 18 6M7 6h11v11",
  sun: "M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z",
  moon: "M20 15.5A8.5 8.5 0 0 1 8.5 4 8.5 8.5 0 1 0 20 15.5Z",
  terminal: "m5 6 5 5-5 5m8 1h6",
  shield: "m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6l8-3Zm-4 9 3 3 5-6",
  files: "M15 8H8a2 2 0 0 0-2 2v11h11V10Zm0 0V3H4v15h2m9-15 5 5v10h-3",
  tabs: "M8 4h12v13H8ZM8 8H3v13h12v-4",
  chats: "M3 4h12v10H9l-4 3v-3H3Zm12 4h6v10h-4l-4 3v-7",
  sparkles: "m13 3 1.5 4.5L19 9l-4.5 1.5L13 15l-1.5-4.5L7 9l4.5-1.5L13 3Zm-8 11 1 3 3 1-3 1-1 3-1-3-3-1 3-1 1-3Zm14-1 1 2.5 2 1-2 1L19 20l-1-2.5-2-1 2-1L19 13Z",
  server: "M3 4h18v5H3Zm0 6h18v5H3Zm0 6h18v5H3Zm14-9h1m-1 6h1m-1 6h1",
  globe: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18ZM5 6.5h14M5 17.5h14",
  window: "M3 4h18v16H3ZM6 7h.1m3 0h.1m3 0h.1",
  lock: "M7 11V7a5 5 0 0 1 10 0v4M5 11h14v10H5Z",
  bolt: "m13 2-9 12h7l-1 8 10-13h-7l1-7Z",
  compact: "M9 6h12M9 11h12M3 17h18M3 21h18M7 7a2 2 0 1 1-4 0 2 2 0 0 1 4 0Zm-3 0 1 1 2-2",
  bug: "M8 9h8v8a4 4 0 0 1-8 0V9Zm1 0V6a3 3 0 0 1 6 0v3M5 11h3m8 0h3M4 16h4m8 0h4M6 21l3-2m6 0 3 2M8 5 6 3m10 2 2-2M12 9v12",
  list: "M8 6h13M8 12h13M8 18h13M3 6h.1M3 12h.1M3 18h.1",
  plus: "M12 4v16M4 12h16",
  workflow: "M9 3h12v12H9ZM9 9H3v12h12v-6m0-9v6m-3-3h6",
  play: "m8 5 11 7-11 7V5Z",
} as const;

export type IconName = keyof typeof iconPaths | "brain" | "stop";
export function Icon({ name, size = 16 }: { name: IconName; size?: number }) {
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={name === "brain" || name === "folder" ? 1.5 : 1.65} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {name === "brain" ? <><path d={brainHalf}/><path d={brainHalf} transform="translate(24 0) scale(-1 1)"/><path d="M12 5.2v13.3"/></> : name === "stop" ? <rect x="7" y="7" width="10" height="10" rx="1" fill="currentColor" stroke="none"/> : <path d={iconPaths[name]} fill={name === "play" ? "currentColor" : "none"}/>}
  </svg>;
}

export function IconButton({ icon, label, size = 16, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { icon: IconName; label: string; size?: number }) {
  return <button type="button" title={label} aria-label={label} data-icon-button="" {...props}><Icon name={icon} size={size}/></button>;
}

export function AgentLogo({ agent, size = 16 }: { agent: string; size?: number }) {
  // These are the same provider assets used by the native app and landing page.
  // eslint-disable-next-line @next/next/no-img-element
  return <img src={`/agents/${agent}.svg`} alt="" width={size} height={size} draggable={false}
    className="[filter:var(--app-logo-filter)] shrink-0 object-contain" data-provider-logo=""/>;
}
