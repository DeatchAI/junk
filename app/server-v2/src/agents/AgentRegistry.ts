import type { AgentKind } from "../protocol/messages";
import type { AgentAdapter } from "./AgentAdapter";
import { ClaudeAdapter } from "./ClaudeAdapter";
import { CursorAdapter } from "./CursorAdapter";
import { CodexAdapter } from "./CodexAdapter";
import { FxAdapter } from "./FxAdapter";
import { GrokAdapter } from "./GrokAdapter";
import { PiAdapter } from "./PiAdapter";
import { AmpAdapter } from "./AmpAdapter";
import { OmpAdapter } from "./OmpAdapter";
import { OpenCodeAdapter } from "./OpenCodeAdapter";

export class AgentRegistry {
  private adapters = new Map<AgentKind, AgentAdapter>();
  private currentAgent: AgentKind = "codex";

  constructor() {
    this.register(new CodexAdapter());
    this.register(new ClaudeAdapter());
    this.register(new CursorAdapter());
    this.register(new GrokAdapter());
    this.register(new FxAdapter());
    this.register(new OpenCodeAdapter());
    this.register(new PiAdapter());
    this.register(new AmpAdapter());
    this.register(new OmpAdapter());
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
