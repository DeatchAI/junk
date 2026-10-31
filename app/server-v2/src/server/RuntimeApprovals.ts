import { type ServerWebSocket, pendingAgentPermissions } from "./RuntimeContext";
import { type AgentPermissionRequest } from "../agents/AgentAdapter";
import { beginQuestionWait } from "../questions/QuestionWait";
import { send } from "./RuntimeHelpers";

export function requestAgentPermission(
  ws: ServerWebSocket,
  request: AgentPermissionRequest,
  runId: string,
  conversationId: string,
) {
  if (ws.readyState !== WebSocket.OPEN) {
    return Promise.reject(new Error("The approval connection was lost. The operation was not approved."));
  }
  const id = "approval_" + crypto.randomUUID();
  return new Promise<boolean>((resolve, reject) => {
    // Human decisions have no deadline, and do not consume the agent's execution budget.
    pendingAgentPermissions.set(id, {
      ws, resolve, reject, runId, conversationId, finishWaiting: beginQuestionWait(runId),
    });
    try {
      send(ws, {
        type: "command_approval_request", id, runId, conversationId,
        command: request.toolName || request.title,
        description: request.description,
        riskLevel: request.riskLevel,
      });
    } catch {
      resolveAgentPermission(id, false, "connection_lost");
    }
  });
}

export function resolveAgentPermission(
  id: string, approved: boolean, reason?: "cancelled" | "connection_lost",
) {
  const pending = pendingAgentPermissions.get(id);
  if (!pending) return;
  pendingAgentPermissions.delete(id);
  pending.finishWaiting();
  const outcome = reason ?? (approved ? "approved" : "declined");
  try {
    send(pending.ws, { type: "command_approval_resolved", id, outcome });
  } catch { /* The socket may already be closed; still settle the agent request. */ }
  if (reason) {
    pending.reject(new Error({
      cancelled: "The approval request was cancelled with the task.",
      connection_lost: "The approval connection was lost. The operation was not approved.",
    }[reason]));
  } else pending.resolve(approved);
}

export function resolvePermissionsForSocket(
  ws: ServerWebSocket, approved: boolean, reason: "cancelled" | "connection_lost" = "connection_lost",
) {
  for (const [id, pending] of pendingAgentPermissions) {
    if (pending.ws === ws) resolveAgentPermission(id, approved, reason);
  }
}

export function resolvePermissionsForRun(runId: string) {
  for (const [id, pending] of pendingAgentPermissions) {
    if (pending.runId === runId) resolveAgentPermission(id, false, "cancelled");
  }
}
