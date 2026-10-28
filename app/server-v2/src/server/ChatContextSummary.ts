import type { ChatRequest, ChatContextSummary } from "../protocol/messages";
import { agentAttachmentContext } from "../agents/AgentPrompt";

/** Counts app-visible input only; native history, file contents and schemas are unknown. */
export function chatContextSummary(request: ChatRequest): ChatContextSummary {
  return {
    runId: request.runId,
    userCharacters: request.text.length,
    instructionCharacters: request.systemPrompt?.trim().length ?? 0,
    attachmentCharacters: agentAttachmentContext(request).length,
    fileCount: request.files?.length ?? 0,
    toolServerCount: request.mcpServers?.filter((server) => server.enabled).length ?? 0,
    permissionMode: request.permissionMode ?? "native",
  };
}
