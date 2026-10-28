import { createHash } from "node:crypto";

export type BranchPoint =
  | { kind: "start" }
  | { kind: "codex"; beforeTurnId: string; previousTurnId?: string }
  | { kind: "claude"; resumeSessionAt: string };

export interface BranchFrom { messageId: string; promptHash: string }
export interface ConversationBranch {
  id: string;
  parentId?: string;
  messageNumber?: number;
  title: string;
}
export interface MessageReference { messageId: string; promptHash: string; canBranch: boolean }
export interface ConversationBranchState {
  type: "conversation_branch_state";
  conversationId: string;
  branches: ConversationBranch[];
  messages: MessageReference[];
}

export function promptFingerprint(text: string) {
  return createHash("sha256").update(text.replaceAll("[Attachment in original session; file not copied]", "").trim()).digest("hex");
}
