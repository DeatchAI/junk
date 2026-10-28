import type { ChatRequest } from "../protocol/messages";

/** Explicit context only. Tool documentation belongs to MCP, not each user turn. */
export function agentAttachmentContext(request: ChatRequest) {
  const sections: string[] = [];
  if (request.attachmentContext?.trim()) sections.push(request.attachmentContext.trim());
  if (request.contextMessages?.length) {
    const transcript = request.contextMessages
      .map((message) => `${message.role === "user" ? "User" : "Assistant"}:\n${message.content}`)
      .join("\n\n");
    sections.push(`Previous conversation (context):\n${transcript}`);
  }
  if (request.files?.length) {
    sections.push(`Attached files:\n${request.files.map((file) =>
      `- ${file.path}${file.mimeType ? ` (${file.mimeType})` : ""}`).join("\n")}`);
  }
  return sections.join("\n\n");
}

/** Content fallback for providers without native file/context blocks. */
export function buildAgentContent(request: ChatRequest) {
  const context = agentAttachmentContext(request);
  return context ? `${context}\n\nCurrent user message:\n${request.text}` : request.text;
}

/** Providers with an instruction channel use buildAgentContent instead. */
export function buildAgentPrompt(request: ChatRequest) {
  const instructions = request.systemPrompt?.trim();
  const content = buildAgentContent(request);
  return instructions ? `Selected instructions:\n${instructions}\n\n${content}` : content;
}

export function resolveWorkspace(requested?: string) {
  if (requested?.trim()) return requested.trim();
  if (Bun.env.DETACH_WORKSPACE?.trim()) return Bun.env.DETACH_WORKSPACE.trim();
  return process.cwd();
}
