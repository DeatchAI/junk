import type { ChatRequest } from "../protocol/messages";

export function buildAgentPrompt(request: ChatRequest) {
  const sections: string[] = [];

  if (request.systemPrompt?.trim()) {
    sections.push(`Task instructions:\n${request.systemPrompt.trim()}`);
  }

  if (request.contextMessages?.length) {
    const transcript = request.contextMessages
      .map((message) => `${message.role === "user" ? "User" : "Assistant"}:\n${message.content}`)
      .join("\n\n");
    sections.push(`Previous conversation. Use this as context, but answer the current user message:\n${transcript}`);
  }

  if (request.files?.length) {
    const fileList = request.files.map((file) => `- ${file.path}${file.mimeType ? ` (${file.mimeType})` : ""}`).join("\n");
    sections.push(`Attached files:\n${fileList}`);
  }

  if (hasDetachBrowserTools(request)) {
    sections.push(browserToolInstructions());
  }

  if (hasDetachMacOSTools(request)) {
    sections.push(macOSToolInstructions());
  }

  if (request.mcpServers?.some((server) => server.enabled && server.id === "detach-secrets-tools")) {
    sections.push([
      "Secure credentials:",
      "- Use detach_secrets_search_credential when a login wall needs a saved credential.",
      "- Use detach_secrets_use_credential only for the exact inspected origin and field refs. It triggers Touch ID; you never receive the credential value.",
      "- After a credential fill, do not request screenshots, snapshots, or extracted text from that document.",
    ].join("\n"));
  }

  sections.push(`Current user message:\n${request.text || ""}`);
  return sections.filter(Boolean).join("\n\n");
}

export function hasDetachBrowserTools(request: ChatRequest) {
  return request.mcpServers?.some((server) => server.enabled && server.id === "detach-browser-tools") ?? false;
}

export function hasDetachMacOSTools(request: ChatRequest) {
  return request.mcpServers?.some((server) => server.enabled && server.id === "detach-macos-tools") ?? false;
}

export function browserToolInstructions() {
  return [
    "Browser automation:",
    "- Use the detach_browser_* MCP tools to work with the user's existing logged-in Chrome profile.",
    "- Call detach_browser_status first. If runtimeConnected is true, the bridge is connected; do not claim it was cancelled and do not ask for an approval prompt.",
    "- Inspect the active tab's automatable field. Chrome-internal pages such as chrome://extensions are restricted; use detach_browser_open_tab or choose an http/https tab from detach_browser_list_tabs.",
    "- Call detach_browser_snapshot on an automatable tab before clicking or typing.",
    "- When a browser tool fails, report its exact error instead of inferring a connection or permission failure.",
    "- Do not load or use a Codex/Claude app browser-control skill, browser plugin, or a fresh browser profile for this task.",
  ].join("\n");
}

export function macOSToolInstructions() {
  return [
    "macOS automation:",
    "- Use detach_macos_* tools for native apps and the desktop. Use detach_browser_* for web-page DOM work when both are available.",
    "- Call detach_macos_status first. Accessibility is required for inspection and input; Screen Recording is required only for screenshots.",
    "- Prefer detach_macos_snapshot followed by ref-based actions. Re-snapshot after the UI changes because refs belong to the latest snapshot.",
    "- Prefer semantic ref clicks over coordinates. Use coordinates only when the accessibility tree has no usable element.",
    "- Secure text fields are intentionally blocked. Do not work around that restriction.",
    "- When a macOS tool fails, report its exact permission or runtime error instead of inferring that the agent cancelled it.",
    "- Do not load another computer-control skill, plugin, or separate automation process for this task.",
  ].join("\n");
}

export function resolveWorkspace(requested?: string) {
  if (requested?.trim()) return requested.trim();
  if (Bun.env.DETACH_WORKSPACE?.trim()) return Bun.env.DETACH_WORKSPACE.trim();
  return process.cwd();
}
