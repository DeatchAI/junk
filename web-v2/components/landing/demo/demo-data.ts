import { agents } from "../data/agents";
export { agents } from "../data/agents";

export type AgentId = (typeof agents)[number]["id"];
export type DemoFile = { id: string; name: string; kind: "image" | "file" | "chat" | "context"; src?: string; path: string; description?: string; icon?: "files" | "tabs" | "chats" | "sparkles" | "server" | "globe" | "window" | "lock" };
export type DemoCommand = { id: string; command: string; title: string; subtitle: string; icon: "bolt" | "compact" | "bug" | "list" | "chat" | "edit" | "shield" | "history" | "terminal" | "file"; kind?: "command" | "workflow" };
export type DemoTranscriptPart = { kind: "text"; text: string } | { kind: "activity"; summary: string; details: string[] };
export type DemoMessage = { id: string; prompt: string; editorText?: string; files: DemoFile[]; commands?: DemoCommand[]; answer: string; agent: AgentId; transcript?: DemoTranscriptPart[] };
export type DemoDraft = { text: string; files: DemoFile[]; commands: DemoCommand[] };
export type DemoBranch = { id: string; label: string; messages: DemoMessage[]; draft: DemoDraft; selected: number };
export type DemoMenu = "agent" | "project" | "attachments" | "commands" | null;
export type DemoAttention =
  | { kind: "approval"; prompt: string; command: string; risk: string }
  | { kind: "question"; prompt: string; options: { label: string; description: string }[] };
export type DemoRun = { id: string; title: string; agent: AgentId; conversationId: string; messageId: string; windowId?: string; branchId?: string; project?: string; state: "running" | "stopped" | "completed" | "approval" | "question"; activity: string; attention?: DemoAttention };

export const sampleFiles: DemoFile[] = [
  { id: "reference", name: "reference.png", kind: "image", src: "/demo/reference.png", path: "acme/design" },
  { id: "page", name: "page.tsx", kind: "file", path: "acme/app" },
  { id: "styles", name: "globals.css", kind: "file", path: "acme/app" },
  { id: "brief", name: "design-brief.md", kind: "file", path: "acme/docs" },
  { id: "conversation", name: "Review checkout flow", kind: "chat", path: "Past conversation" },
];

export const sampleConnections: DemoFile[] = [
  { id: "mcp-github", name: "GitHub", kind: "context", icon: "server", path: "Connected MCP server", description: "Repository and pull request context." },
  { id: "mcp-linear", name: "Linear", kind: "context", icon: "server", path: "Connected MCP server", description: "Project issues and task context." },
];

export const historyItems = [
  { id: "landing", title: "Polish the landing page", project: "acme", agent: "codex" as AgentId },
  { id: "checkout", title: "Review checkout flow", project: "acme", agent: "claude" as AgentId },
  { id: "spacing", title: "Add a little breathing room", project: "acme", agent: "codex" as AgentId },
  { id: "project", title: "Build the project page", project: "portfolio", agent: "codex" as AgentId },
  { id: "navigation", title: "Simplify navigation", project: "portfolio", agent: "claude" as AgentId },
];

export const commands: DemoCommand[] = [
  { id: "explain", command: "explain", title: "Explain", subtitle: "Break down the selected context clearly", icon: "bolt" },
  { id: "simplify", command: "simplify", title: "Simplify", subtitle: "Rewrite in simpler language", icon: "bolt" },
  { id: "code-review", command: "code-review", title: "Code Review", subtitle: "Review for bugs, risks, and missing tests", icon: "bolt" },
  { id: "compact-context", command: "compact-context", title: "Compact Context", subtitle: "Summarize the useful context for the next turn", icon: "compact" },
  { id: "debug", command: "debug", title: "Debug", subtitle: "Trace the likely cause and propose a fix", icon: "bug" },
  { id: "plan", command: "plan", title: "Plan", subtitle: "Make a concise implementation plan first", icon: "list" },
];

export const sampleRuns: DemoRun[] = [
  { id: "checkout-run", title: "Review checkout flow", agent: "claude", conversationId: "checkout", messageId: "checkout-u1", state: "running", activity: "Reviewing checkout components" },
  { id: "project-run", title: "Build the project page", agent: "codex", conversationId: "project", messageId: "project-u1", state: "running", activity: "Working on the project page" },
  { id: "navigation-run", title: "Simplify navigation", agent: "grok", conversationId: "navigation", messageId: "navigation-u1", state: "completed", activity: "Completed" },
];

export function sampleConversation(agent: AgentId = "codex"): DemoMessage[] {
  return [
    { id: "past-1", prompt: "Polish the landing page. Keep the typography quiet and give the layout more breathing room.", files: [],
      answer: "I’ll keep the typography quiet and give the layout a little more breathing room.", agent },
    { id: "past-2", prompt: "Use this reference for the project cards. Keep the existing spacing system.", files: [sampleFiles[0], sampleFiles[1]],
      answer: "I’ll use this reference for the project cards and keep the existing spacing system.", agent },
  ];
}

export function emptyBranch(id = "original"): DemoBranch {
  return { id, label: "Original conversation", messages: [], draft: { text: "", files: [], commands: [] }, selected: -1 };
}
