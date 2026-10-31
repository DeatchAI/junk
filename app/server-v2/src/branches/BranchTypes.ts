import { createHash } from "node:crypto";

export type BranchPoint =
  | { kind: "start" }
  | { kind: "codex"; beforeTurnId?: string; previousTurnId?: string }
  | { kind: "claude"; resumeSessionAt: string };

export interface BranchFrom { messageId: string; promptHash: string; afterResponse?: boolean }
export interface ConversationBranch {
  id: string;
  parentId?: string;
  messageNumber?: number;
  title: string;
}
export interface MessageReference { messageId: string; promptHash: string; canBranch: boolean; canBranchAfter?: boolean }
export interface ConversationBranchState {
  type: "conversation_branch_state";
  conversationId: string;
  branches: ConversationBranch[];
  messages: MessageReference[];
}

/** A reply branch retains all adjacent assistant parts and excludes the next user turn. */
export function responseBranchPoint(messages: { role: string; branchPoint?: BranchPoint }[], target: number): BranchPoint | undefined {
  let end = target + 1;
  while (messages[end]?.role === "assistant") end++;
  if (end === target + 1) return undefined;
  const point = messages[target]?.branchPoint;
  if (point?.kind === "codex" && point.beforeTurnId) {
    const next = messages[end]?.branchPoint;
    if (messages[end] && (next?.kind !== "codex" || !next.beforeTurnId)) return undefined;
    return { kind: "codex", beforeTurnId: next?.kind === "codex" ? next.beforeTurnId : undefined,
      previousTurnId: point.beforeTurnId };
  }
  return messages.slice(target + 1, end).reverse().find(message => message.branchPoint?.kind === "claude")?.branchPoint;
}

export function promptFingerprint(text: string) {
  return createHash("sha256").update(text.replaceAll("[Attachment in original session; file not copied]", "").trim()).digest("hex");
}
