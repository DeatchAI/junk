import type { AgentKind, ConversationContextMessage, MessagePart } from "../protocol/messages";
import type { BranchPoint } from "../branches/BranchTypes";

export type ImportProvider = AgentKind;
export const IMPORT_PROVIDERS: ImportProvider[] = ["codex", "claude", "opencode", "pi", "omp", "amp", "fx", "grok"];
export interface ImportedMessage extends ConversationContextMessage { createdAt: number; parts?: MessagePart[]; branchPoint?: BranchPoint }
export interface ExternalChat {
  provider: ImportProvider;
  sourceId: string;
  sourceKey: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  workspacePath?: string;
  model?: string;
  canResume: boolean;
  warning?: string;
  /** Private source reference; never accepted as a path from a socket. */
  locator?: string;
  active?: boolean;
}
export interface ImportCandidate extends Omit<ExternalChat, "sourceKey" | "locator" | "sourceId"> {
  id: string;
  imported: boolean;
}
export interface ImportSource {
  provider: ImportProvider;
  discover(): Promise<{ chats: ExternalChat[]; notices?: string[]; complete?: boolean }>;
  read(chat: ExternalChat): Promise<ImportedMessage[]>;
}
export interface ConversationImportSource { provider: ImportProvider; canResume: boolean; warning?: string }
export interface NativeSession { id: string; workspacePath: string }

export type ChatImportClientMessage =
  | { type: "discover_chats"; requestId: string; provider?: ImportProvider }
  | { type: "preview_chat_import"; requestId: string; candidateId: string }
  | { type: "import_chats"; requestId: string; candidateIds: string[] };
export type ChatImportServerMessage =
  | { type: "chat_import_discovered"; requestId: string; candidates: ImportCandidate[]; notices: string[] }
  | { type: "chat_import_preview"; requestId: string; candidateId: string; messages: ImportedMessage[]; messageCount: number }
  | { type: "chat_import_completed"; requestId: string; imported: number; skipped: number; errors: string[]; completedIds: string[] }
  | { type: "chat_import_error"; requestId: string; error: string };

export function importProvider(value: unknown): value is ImportProvider {
  return typeof value === "string" && IMPORT_PROVIDERS.includes(value as ImportProvider);
}
export function knownProvider(value: unknown): value is AgentKind {
  return typeof value === "string" && ["codex", "claude", "cursor", "opencode", "grok", "pi", "omp", "amp", "fx"].includes(value);
}
