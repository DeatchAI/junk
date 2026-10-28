import type { AgentActivityEvent, AgentKind, ChatRequest } from "../protocol/messages";
import type { AgentQuestionAnswers, AgentQuestionRequest } from "../questions/AgentQuestion";

export interface AgentStreamCallbacks {
  /** Emitted only after the provider acknowledges its saved session identity. */
  onSession?(session: AgentNativeSession): void;
  onActivity(status: string, toolName?: string, event?: AgentActivityEvent): void;
  onChunk(text: string): void;
  /** Provider-generated metadata, never response text or tool activity. */
  onTitle?(title: string): void;
  onPermission?(request: AgentPermissionRequest): Promise<boolean>;
  onQuestion?(request: AgentQuestionRequest): Promise<AgentQuestionAnswers | null>;
}

export interface AgentNativeSession { id: string; workspacePath?: string; path?: string; title?: string; canResume?: boolean }

export interface AgentPermissionRequest {
  title: string;
  description: string;
  riskLevel: "safe" | "normal" | "dangerous";
  toolName?: string;
}

export interface AgentRun {
  cancel(): void;
  finished: Promise<AgentRunResult>;
}

export interface AgentRunResult {
  text: string;
}

export interface AgentAdapter {
  readonly id: AgentKind;
  readonly displayName: string;
  isAvailable(): Promise<boolean>;
  run(request: ChatRequest, callbacks: AgentStreamCallbacks): AgentRun;
}
