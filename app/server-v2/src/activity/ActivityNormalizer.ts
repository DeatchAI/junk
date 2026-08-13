import type {
  AgentActivityAction,
  AgentActivityEvent,
  AgentActivityKind,
  AgentKind,
} from "../protocol/messages";

const TOOL_ACTIONS: Record<string, AgentActivityAction> = {
  image: "image",
  plan: "plan",
  terminal: "terminal",
  file: "edit",
  Bash: "terminal",
  Read: "read",
  Grep: "search",
  Glob: "search",
  Edit: "edit",
  MultiEdit: "edit",
  Write: "edit",
  detach_browser_execute: "browser.inspect",
  detach_macos_status: "desktop.inspect",
  detach_macos_list_apps: "desktop.inspect",
  detach_macos_list_windows: "desktop.inspect",
  detach_macos_snapshot: "desktop.inspect",
  detach_macos_screenshot: "browser.capture",
  detach_macos_activate_app: "desktop.interact",
  detach_macos_open_app: "desktop.interact",
  detach_macos_click: "desktop.interact",
  detach_macos_type: "desktop.interact",
  detach_macos_key: "desktop.interact",
  detach_macos_scroll: "desktop.interact",
  detach_secrets_search_credential: "credential",
  detach_secrets_use_credential: "credential",
};

const TOOL_TITLES: Record<string, string> = {
  detach_browser_execute: "Working in the browser",
  detach_macos_status: "Checking macOS access",
  detach_macos_list_apps: "Reviewing open Mac apps",
  detach_macos_list_windows: "Reviewing app windows",
  detach_macos_activate_app: "Bringing the app forward",
  detach_macos_open_app: "Opening a Mac app",
  detach_macos_snapshot: "Inspecting the active Mac app",
  detach_macos_screenshot: "Capturing the Mac screen",
  detach_macos_click: "Clicking in the Mac app",
  detach_macos_type: "Entering text in the Mac app",
  detach_macos_key: "Using a keyboard shortcut",
  detach_macos_scroll: "Scrolling the Mac app",
  detach_secrets_search_credential: "Finding a saved credential",
  detach_secrets_use_credential: "Requesting secure credential access",
};

export function normalizeAgentActivity(
  agent: AgentKind,
  status: string,
  toolName?: string,
  event?: AgentActivityEvent,
): AgentActivityEvent {
  const incomingTitle = event?.title?.trim() || status.trim() || "Working";
  const action = event?.action
    ?? (event?.kind === "mcp_tool" ? actionForTool(toolName) : undefined)
    ?? actionForKind(event?.kind, incomingTitle)
    ?? actionForTitle(incomingTitle)
    ?? actionForTool(toolName)
    ?? "generic";
  const title = preferredToolTitle(incomingTitle, toolName);

  return {
    ...event,
    id: event?.id,
    agent,
    kind: event?.kind ?? kindForAction(action),
    action,
    phase: event?.phase ?? "started",
    title,
    subtitle: event?.subtitle,
    toolName: event?.toolName ?? toolName,
    userFacing: event?.userFacing ?? true,
    sourceEventType: event?.sourceEventType,
    sourceItemType: event?.sourceItemType,
    details: event?.details,
  };
}

function preferredToolTitle(title: string, toolName?: string) {
  if (!toolName) return title;
  const normalized = toolName.replace(/^mcp__[^_]+__/, "");
  const preferred = TOOL_TITLES[normalized];
  if (!preferred) return title;
  return /^(using|running|calling|executing)( a| the)? tool\b/i.test(title)
    || title.trim().toLowerCase() === normalized.toLowerCase()
    ? preferred
    : title;
}

export function actionForTool(toolName?: string): AgentActivityAction | undefined {
  if (!toolName) return undefined;
  const normalized = toolName.replace(/^mcp__[^_]+__/, "");
  if (TOOL_ACTIONS[normalized]) return TOOL_ACTIONS[normalized];

  const lower = normalized.toLowerCase();
  if (/(search|grep|find|query)/.test(lower)) return "search";
  if (/(read|fetch|get|list|inspect|snapshot|status)/.test(lower)) return "read";
  if (/(create|write|add|insert)/.test(lower)) return "create";
  if (/(edit|update|patch|replace)/.test(lower)) return "edit";
  if (/(delete|remove|trash)/.test(lower)) return "delete";
  if (/(image|photo|screenshot|capture)/.test(lower)) return "image";
  if (/(credential|secret|password|auth)/.test(lower)) return "credential";
  if (/(browser|web|chrome)/.test(lower)) return "browser.inspect";
  if (/(macos|desktop|computer)/.test(lower)) return "desktop.interact";
  if (/(terminal|shell|bash|command|exec)/.test(lower)) return "terminal";
  return "connector";
}

function actionForKind(
  kind: AgentActivityKind | undefined,
  title: string,
): AgentActivityAction | undefined {
  switch (kind) {
    case "attachment": return "image";
    case "command": return actionForTitle(title) ?? "terminal";
    case "file_change": return actionForTitle(title) ?? "edit";
    case "mcp_tool": return undefined;
    case "plan": return "plan";
    case "error": return "error";
    case "lifecycle": return actionForTitle(title) ?? "prepare";
    case "status": return actionForTitle(title) ?? "generic";
    default: return undefined;
  }
}

function actionForTitle(title: string): AgentActivityAction | undefined {
  const lower = title.toLowerCase();
  if (/(prepar|starting|connecting|initializ)/.test(lower)) return "prepare";
  if (/(thinking|reasoning|considering)/.test(lower)) return "think";
  if (/(planning|plan:|next step)/.test(lower)) return "plan";
  if (/(searching|finding|looking for|grep)/.test(lower)) return "search";
  if (/(reading|reviewing|inspecting|checking|listing)/.test(lower)) return "read";
  if (/(creating|adding|writing a new)/.test(lower)) return "create";
  if (/(editing|updating|patching|modifying)/.test(lower)) return "edit";
  if (/(deleting|removing)/.test(lower)) return "delete";
  if (/(building|compiling|packaging)/.test(lower)) return "build";
  if (/(testing|running tests|validating|verifying)/.test(lower)) return "test";
  if (/(waiting|still working)/.test(lower)) return "wait";
  if (/(failed|error|could not)/.test(lower)) return "error";
  if (/(image|screenshot|photo)/.test(lower)) return "image";
  if (/(credential|secret|touch id|password)/.test(lower)) return "credential";
  if (/(browser|web page|tab)/.test(lower)) return "browser.inspect";
  if (/(macos|desktop|screen|app)/.test(lower)) return "desktop.inspect";
  if (/(running|command|terminal|shell)/.test(lower)) return "terminal";
  return undefined;
}

function kindForAction(action: AgentActivityAction): AgentActivityKind {
  if (action === "prepare" || action === "think") return "lifecycle";
  if (action === "plan") return "plan";
  if (action === "terminal" || action === "build" || action === "test") return "command";
  if (action === "create" || action === "edit" || action === "delete") return "file_change";
  if (action === "image") return "attachment";
  if (action === "error") return "error";
  if (action === "generic" || action === "wait") return "status";
  return "mcp_tool";
}
