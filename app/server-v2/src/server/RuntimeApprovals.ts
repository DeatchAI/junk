import { type ServerWebSocket, pendingAgentPermissions } from "./RuntimeContext";
import { type AgentPermissionRequest } from "../agents/AgentAdapter";
import { send } from "./RuntimeHelpers";


export function requestAgentPermission(
  ws: ServerWebSocket,
  request: AgentPermissionRequest,
  runId: string,
  conversationId: string
) {
  const id = `approval_${crypto.randomUUID()}`;

  return new Promise<boolean>((resolve, reject) => {
    const timeout = setTimeout(() => resolveAgentPermission(id, false, "timed_out"), 60_000);
    pendingAgentPermissions.set(id, { ws, resolve, reject, timeout, runId, conversationId });
    send(ws, {
      type: "command_approval_request",
      id,
      runId,
      conversationId,
      command: request.toolName || request.title,
      description: request.description,
      riskLevel: request.riskLevel,
    });
  });
}


export function resolveAgentPermission(id: string, approved: boolean, reason: "timed_out" | "cancelled" | "connection_lost" | undefined = undefined) {
  const pending = pendingAgentPermissions.get(id);
  if (!pending) return;
  clearTimeout(pending.timeout);
  pendingAgentPermissions.delete(id);
  const outcome = reason ?? (approved ? "approved" : "declined");
  try {
    send(pending.ws, { type: "command_approval_resolved", id, outcome });
  } catch { /* The socket may already be closed; still settle the agent request. */ }
  if (reason) {
    pending.reject(new Error({
      timed_out: "The approval request timed out without an answer. The operation was not approved.",
      cancelled: "The approval request was cancelled with the task.",
      connection_lost: "The approval connection was lost. The operation was not approved.",
    }[reason]));
  } else pending.resolve(approved);
}


export function resolvePermissionsForSocket(ws: ServerWebSocket, approved: boolean, reason: "cancelled" | "connection_lost" = "connection_lost") {
  for (const [id, pending] of pendingAgentPermissions) {
    if (pending.ws === ws) resolveAgentPermission(id, approved, reason);
  }
}
