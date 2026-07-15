import type { AgentKind } from "../protocol/messages";
import type { AgentAdapter } from "./AgentAdapter";
import { ClaudeAdapter } from "./ClaudeAdapter";
import { CodexAdapter } from "./CodexAdapter";
import { GrokAdapter } from "./GrokAdapter";

export class AgentRegistry {
  private adapters = new Map<AgentKind, AgentAdapter>();
  private currentAgent: AgentKind = "codex";

  constructor() {
    this.register(new CodexAdapter());
    this.register(new ClaudeAdapter());
    this.register(new GrokAdapter());
  }

  register(adapter: AgentAdapter) {
    this.adapters.set(adapter.id, adapter);
  }

  setCurrentAgent(agent: AgentKind) {
    if (this.adapters.has(agent)) {
      this.currentAgent = agent;
    }
  }

  has(agent: string): agent is AgentKind {
    return this.adapters.has(agent as AgentKind);
  }

  getCurrentAgent() {
    return this.currentAgent;
  }

  get(agent?: AgentKind) {
    const selected = agent ?? this.currentAgent;
    const adapter = this.adapters.get(selected);
    if (!adapter) {
      throw new Error(`Unknown agent: ${selected}`);
    }
    return adapter;
  }
}
