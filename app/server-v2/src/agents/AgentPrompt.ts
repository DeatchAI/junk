import type { ChatRequest } from "../protocol/messages";
import browserSkill from "../browser/skill/SKILL.md" with { type: "text" };
import { CAPABILITY_BROKER_ID } from "../capabilities/CapabilityConstants";

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

  if (hasDetachCapabilityBroker(request)) {
    sections.push(capabilityToolInstructions());
  }

  if (request.mcpServers?.some((server) => server.enabled && server.id === "detach-secrets-tools")) {
    sections.push([
      "Secure credentials:",
      "- Use detach_secrets_search_credential when a login wall needs a saved credential.",
      "- Describe the username, password, and submit controls before Touch ID. Pass all retained refs to detach_secrets_use_credential so fill and submit happen atomically; you never receive credential values.",
      "- Read its structured submitted/navigation/inspection result. URL, title, page.waitForURL(), and navigation events remain safe while DOM inspection is locked.",
      "- After a credential fill, do not request screenshots, snapshots, or extracted text until navigation unlocks the new document.",
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

export function hasDetachCapabilityBroker(request: ChatRequest) {
  return request.mcpServers?.some((server) => server.enabled && server.id === CAPABILITY_BROKER_ID) ?? false;
}

export function capabilityToolInstructions() {
  return [
    "Detach capability directory:",
    "- Detach provides Browser, macOS, and Secrets capabilities through one compact broker; do not ask the user to attach an MCP server before trying them.",
    "- Call detach_capabilities_list when you need to find the right capability or verify its connection.",
    "- Call detach_capability_describe for only the capability you need. Its response contains the operation schemas; do not assume unrelated operations are available without describing them.",
    "- Call detach_capability_invoke with the described capability ID, operation name, and arguments. Browser calls use the user's focused signed-in Chrome; macOS calls use the connected Detach app; Secrets uses the dedicated Touch ID flow and never returns credential values.",
    "- Use Browser for web-page DOM work and macOS for native app UI. If a capability reports needs_connection, surface the exact connection hint after the invocation/list check.",
  ].join("\n");
}

export function browserToolInstructions() {
  return `Bundled browser skill:\n${browserSkill.trim()}`;
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
