import type { ChatRequest } from "../../protocol/messages";
import { agentAttachmentContext } from "../AgentPrompt";

export function buildCodexPrompt(request: ChatRequest) {
  return request.text;
}

/** Native context keeps selected instructions and attachment data out of user text. */
export function codexAdditionalContext(request: ChatRequest) {
  const instructions = request.systemPrompt?.trim();
  const attachments = agentAttachmentContext(request);
  if (!instructions && !attachments) return undefined;
  return {
    ...(instructions ? { "detach.selected-instructions": { kind: "application", value: instructions } } : {}),
    ...(attachments ? { "detach.attachments": { kind: "untrusted", value: attachments } } : {}),
  };
}
