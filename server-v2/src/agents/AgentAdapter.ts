import type { AgentActivityEvent, AgentKind, ChatRequest } from "../protocol/messages";

export interface AgentStreamCallbacks {
  onActivity(status: string, toolName?: string, event?: AgentActivityEvent): void;
  onChunk(text: string): void;
  onPermission?(request: AgentPermissionRequest): Promise<boolean>;
}

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
