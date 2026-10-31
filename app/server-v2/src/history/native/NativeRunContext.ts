import type { ImportedMessage } from "../../imports/ImportTypes";
import type { MessagePart } from "../../protocol/messages";
import { resolve } from "node:path";
import { realpathSync } from "node:fs";
import type { AgentKind, ChatRequest, ConversationContextMessage } from "../../protocol/messages";
import type { AgentNativeSession } from "../../agents/AgentAdapter";
import type { SqliteHistory } from "../SqliteHistory";
import { resolveWorkspace } from "../../agents/AgentPrompt";
import { existingWorkspace } from "../../imports/Transcript";
import { isNativeID } from "./NativeIdentity";
import type { NativeHistoryService } from "./NativeHistoryService";
import { legacyContext } from "../LegacyContext";
import { promptFingerprint, responseBranchPoint, type BranchPoint } from "../../branches/BranchTypes";

const workspaceIdentity = (path: string) => { try { return realpathSync(path); } catch { return resolve(path); } };

export class NativeRunContext {
  conversation = { id: "", title: "" };
  bound = false;
  contextMessages: ConversationContextMessage[] = [];
  nativeSessionID?: string;
  resumeSessionID?: string;
  forkPoint?: BranchPoint;
  nativeSessionPath?: string;
  private startedAt = Date.now();
  private baseline: ImportedMessage[] = [];
  private previousID?: string;
  get messageOrdinal() { return this.baseline.filter(message => message.role === "user").length; }
  private cached = false;
  private branch?: { parentId: string; parentSessionId: string; messageId: string; messageNumber: number };
  private constructor(readonly service: NativeHistoryService, readonly provider: AgentKind,
    readonly workspacePath: string, readonly prompt: string, readonly model: string | undefined, readonly runID: string) {
    this.conversation = { id: `pending_${runID}`, title: prompt.trim().slice(0, 100) || "New chat" };
  }

  static async prepare(service: NativeHistoryService, legacy: SqliteHistory, request: ChatRequest, provider: AgentKind, runID: string) {
    let source = request.conversationId ? service.index.source(request.conversationId) : undefined;
    if (!source && request.conversationId && isNativeID(request.conversationId)) {
      // Recover a provider-owned identity removed by an older/incomplete index refresh.
      await service.refresh(true);
      source = service.index.source(request.conversationId);
    }
    const legacyEntry = request.conversationId && !source ? legacy.get(request.conversationId) : undefined;
    if (request.branchFrom && !source) throw new Error("Open a saved agent conversation before editing a past message.");
    if (request.conversationId && !source && !legacyEntry) throw new Error("Conversation is unavailable. Refresh history or start a new chat.");
    if (source && source.provider !== provider) throw new Error(`This is a ${source.provider} session. Start a new chat to use ${provider}.`);
    const workspace = workspaceIdentity(resolveWorkspace(request.workspacePath ?? source?.workspacePath ?? legacyEntry?.conversation.workspacePath));
    if (!await existingWorkspace(workspace)) throw new Error("Choose an existing project folder before starting this task.");
    if (source?.workspacePath && workspaceIdentity(source.workspacePath) !== workspace) throw new Error("This session belongs to another project. Restore its original folder or start a new chat.");
    const context = new NativeRunContext(service, provider, workspace, request.displayText?.trim() || request.text || "", request.model, runID);
    if (source) {
      if (source.active) throw new Error("This session is running in another client. Finish it there before continuing in Detach.");
      const entry = await service.get(request.conversationId!);
      if (!entry?.conversation.canResume) throw new Error(entry?.conversation.historyWarning || "This provider cannot resume this session. Its history remains readable.");
      context.resumeSessionID = source.sourceId;
      context.nativeSessionPath = service.index.source(request.conversationId!)?.locator ?? source.locator;
      let baseline = entry.messages;
      if (request.branchFrom) {
        const target = entry.messages.findIndex((message) => message.id === request.branchFrom!.messageId && message.role === "user");
        const message = entry.messages[target];
        if (!message || promptFingerprint(message.content) !== request.branchFrom.promptHash) {
          throw new Error("This message changed in the agent. Reopen the conversation before editing it.");
        }
        if (request.branchFrom.afterResponse !== undefined && typeof request.branchFrom.afterResponse !== "boolean") {
          throw new Error("Invalid conversation branch position.");
        }
        const point = request.branchFrom.afterResponse ? responseBranchPoint(entry.messages, target) : message.branchPoint;
        if (!point || (point.kind !== "start" && point.kind !== provider)) {
          throw new Error("This agent cannot branch at this message. The original conversation was kept intact.");
        }
        context.forkPoint = point;
        if (point.kind === "start") context.resumeSessionID = undefined;
        let end = target;
        if (request.branchFrom.afterResponse) {
          end = target + 1;
          while (entry.messages[end]?.role === "assistant") end++;
        }
        baseline = entry.messages.slice(0, end);
        context.branch = { parentId: entry.conversation.id, parentSessionId: source.sourceId,
          messageId: message.id, messageNumber: entry.messages.slice(0, target + 1).filter((row) => row.role === "user").length };
      } else {
        context.nativeSessionID = source.sourceId;
        context.conversation = { id: entry.conversation.id, title: entry.conversation.title || context.conversation.title };
      }
      context.baseline = baseline.map((message) => ({ role: message.role, content: message.content,
        parts: message.parts, branchPoint: message.branchPoint, createdAt: message.created_at }));
      service.lock(entry.conversation.id); context.previousID = entry.conversation.id;
    } else if (legacyEntry) {
      // Existing Detach-only chats are preserved. Continue as a NEW provider-native session.
      context.contextMessages = legacyContext(legacyEntry.messages);
    }
    return context;
  }

  bind(session: AgentNativeSession) {
    if (!session.id?.trim() || session.id.length > 512) throw new Error("Provider returned an invalid saved-session identity.");
    if (this.nativeSessionID && session.id !== this.nativeSessionID) throw new Error("Provider resumed a different session. The task was not rebound.");
    if (this.branch && session.id === this.branch.parentSessionId) throw new Error("The provider did not create an independent branch. The original conversation was kept intact.");
    if (session.workspacePath && workspaceIdentity(session.workspacePath) !== this.workspacePath) throw new Error("Provider acknowledged a different project folder.");
    const id = this.service.register(this.provider, session.id, this.workspacePath, this.prompt,
      { locator: session.path, title: session.title, model: this.model, canResume: session.canResume });
    this.bound = true; this.nativeSessionID = session.id;
    this.nativeSessionPath = session.path ?? this.nativeSessionPath;
    this.conversation.id = id;
    this.conversation.title = this.service.index.source(id)?.title || this.conversation.title;
    if (this.branch) this.service.index.branches.add(id, this.branch.parentId, this.branch.messageId, this.branch.messageNumber);
  }
  cacheResponse(text: string, parts?: MessagePart[]) {
    if (!this.bound || this.cached) return;
    const source = this.service.index.source(this.conversation.id); if (!source) return;
    // A mirror of provider-confirmed streamed output, replaced by a fresh source read after completion.
    this.service.index.cache({ ...source, updatedAt: Date.now() }, [...this.baseline,
      { role: "user", content: this.prompt, createdAt: this.startedAt },
      ...(text || parts?.length ? [{ role: "assistant" as const, content: text, parts, createdAt: Date.now() }] : []),
    ]);
    this.cached = true;
  }
  async release() {
    if (this.bound) await this.service.finish(this.conversation.id);
    if (this.previousID && this.previousID !== this.conversation.id) await this.service.finish(this.previousID);
    else if (!this.bound && this.previousID) await this.service.finish(this.previousID);
  }
}

