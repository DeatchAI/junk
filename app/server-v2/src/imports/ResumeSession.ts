import { resolve } from "node:path";
import type { SqliteHistory } from "../history/SqliteHistory";
import type { AgentKind, ChatRequest } from "../protocol/messages";
import { existingWorkspace } from "./Transcript";

export async function resolveHistorySession(history: SqliteHistory, request: ChatRequest, provider: AgentKind) {
  if (!request.conversationId) return undefined;
  const conversation = history.get(request.conversationId)?.conversation;
  const session = history.metadata.session(request.conversationId, provider);
  if (!session) {
    if (conversation?.importSource && !await existingWorkspace(request.workspacePath ?? conversation.workspacePath)) {
      throw new Error("Choose an existing working folder before continuing this imported conversation.");
    }
    return undefined;
  }
  if (request.workspacePath && resolve(request.workspacePath) !== resolve(session.workspacePath)) {
    throw new Error("This imported session belongs to another project. Restore its original working folder or start a new chat.");
  }
  if (!await existingWorkspace(session.workspacePath)) throw new Error("The imported session's project folder is unavailable. Restore the folder or start a new chat using its transcript.");
  return session;
}
