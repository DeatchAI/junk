import { parseAgentQuestions, validateAnswers, type AgentQuestionAnswers, type AgentQuestionClientMessage, type AgentQuestionRequest, type AgentQuestionServerMessage } from "./AgentQuestion";
import { beginQuestionWait, clearQuestionWait } from "./QuestionWait";

interface RunContext<Socket> {
  ws: Socket;
  conversationId: string;
  agent: string;
  taskTitle?: string;
}

interface PendingQuestion<Socket> extends RunContext<Socket> {
  runId: string;
  request: AgentQuestionRequest;
  finishWaiting(): void;
  resolve(answers: AgentQuestionAnswers | null): void;
}

/** Questions belong to a live run and its originating connection, never to a global chat. */
export class AgentQuestionBroker<Socket> {
  private readonly runs = new Map<string, RunContext<Socket>>();
  private readonly pending = new Map<string, PendingQuestion<Socket>>();

  constructor(
    private readonly send: (ws: Socket, message: AgentQuestionServerMessage) => void,
    private readonly remember?: (conversationId: string, text: string) => void,
  ) {}

  registerRun(runId: string, context: RunContext<Socket>) {
    if (this.runs.has(runId)) throw new Error("This agent run is already active.");
    this.runs.set(runId, context);
  }

  bindConversation(runId: string, conversationId: string, taskTitle?: string) {
    const context = this.runs.get(runId);
    if (context) { context.conversationId = conversationId; context.taskTitle = taskTitle ?? context.taskTitle; }
    for (const pending of this.pending.values()) if (pending.runId === runId) {
      pending.conversationId = conversationId; pending.taskTitle = taskTitle ?? pending.taskTitle;
    }
  }

  ask(runId: string, value: unknown): Promise<AgentQuestionAnswers | null> {
    const context = this.runs.get(runId);
    if (!context) return Promise.reject(new Error("Clarification requires an active Detach task."));
    const request = parseAgentQuestions(value);
    const id = `question_${crypto.randomUUID()}`;
    return new Promise((resolve) => {
      this.pending.set(id, { ...context, runId, request, resolve, finishWaiting: beginQuestionWait(runId) });
      try {
        this.send(context.ws, { type: "agent_question", id, runId, conversationId: context.conversationId,
          agent: context.agent, taskTitle: context.taskTitle, questions: request.questions });
      } catch {
        this.finish(id, null);
      }
    });
  }

  respond(ws: Socket, message: AgentQuestionClientMessage) {
    const pending = this.pending.get(message.requestId);
    if (!pending || pending.ws !== ws || pending.runId !== message.runId) return false;
    if (message.cancelled === true) {
      this.finish(message.requestId, null);
      return true;
    }
    let answers: AgentQuestionAnswers;
    try { answers = validateAnswers(pending.request, message.answers); }
    catch (error) {
      this.send(ws, { type: "agent_question_error", id: message.requestId, error: (error as Error).message });
      return false;
    }
    const text = pending.request.questions.filter((question) => !question.isSecret)
      .map((question) => `${question.question}\n${answers[question.id]!.answers[0]}`).join("\n\n");
    try { if (text) this.remember?.(pending.conversationId, `Clarification:\n${text}`); }
    catch { /* A history write failure must not strand a live agent question. */ }
    this.finish(message.requestId, answers);
    return true;
  }

  endRun(runId: string) {
    this.runs.delete(runId);
    for (const [id, pending] of this.pending) if (pending.runId === runId) this.finish(id, null);
    clearQuestionWait(runId);
  }

  endSocket(ws: Socket) {
    for (const [runId, context] of this.runs) if (context.ws === ws) this.endRun(runId);
  }

  private finish(id: string, answers: AgentQuestionAnswers | null) {
    const pending = this.pending.get(id);
    if (!pending) return;
    this.pending.delete(id);
    pending.finishWaiting();
    try { this.send(pending.ws, { type: "agent_question_resolved", id, runId: pending.runId }); }
    catch { /* The connection may have closed while the question was visible. */ }
    pending.resolve(answers);
  }
}
