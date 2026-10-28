import type { AgentKind } from "../protocol/messages";
import type { SqliteHistory } from "../history/SqliteHistory";
import { cleanTitle } from "./TitleText";

export interface TitleRequest { agent: AgentKind; model?: string; message: string }
export interface ConversationTitleUpdate { type: "conversation_title"; conversationId: string; title: string }

/** Best-effort metadata work, independent of agent runs, sockets and approvals. */
export class ConversationTitleService {
  private readonly pending = new Map<string, Promise<void>>();
  constructor(
    private readonly history: SqliteHistory,
    private readonly generate: (request: TitleRequest) => Promise<string | undefined>,
    private readonly publish: (update: ConversationTitleUpdate) => void,
  ) {}

  schedule(conversationId: string, agent: AgentKind, model?: string) {
    if (agent === "fx") return Promise.resolve();
    const pending = this.pending.get(conversationId);
    if (pending) return pending;
    const claim = this.history.claimTitleGeneration(conversationId);
    if (!claim) return Promise.resolve();
    const task = Promise.resolve().then(async () => {
      const result = await this.generate({ agent, model, message: claim.message });
      const title = result ? cleanTitle(result) : undefined;
      if (title && this.history.setGeneratedTitle(conversationId, claim.title, title)) {
        this.publish({ type: "conversation_title", conversationId, title });
      }
    }).catch(() => {
      // Naming failures must never become task errors or leak prompt/credential data.
    }).finally(() => { this.pending.delete(conversationId); });
    this.pending.set(conversationId, task);
    return task;
  }

  acceptProviderTitle(conversationId: string, value: string) {
    const title = cleanTitle(value);
    if (!title) return;
    const claim = this.history.claimTitleGeneration(conversationId);
    if (claim && this.history.setGeneratedTitle(conversationId, claim.title, title)) {
      this.publish({ type: "conversation_title", conversationId, title });
    }
  }
}
