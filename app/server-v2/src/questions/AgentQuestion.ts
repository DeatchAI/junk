export interface AgentQuestionOption {
  label: string;
  description?: string;
}

export interface AgentQuestion {
  id: string;
  header: string;
  question: string;
  options?: AgentQuestionOption[];
  isSecret?: boolean;
}

export interface AgentQuestionRequest {
  questions: AgentQuestion[];
}

export type AgentQuestionAnswers = Record<string, { answers: string[] }>;

export type AgentQuestionClientMessage = {
  type: "agent_question_response";
  requestId: string;
  runId: string;
  answers?: AgentQuestionAnswers;
  cancelled?: boolean;
};

export type AgentQuestionServerMessage =
  | { type: "agent_question"; id: string; runId: string; conversationId: string; agent: string; taskTitle?: string; questions: AgentQuestion[] }
  | { type: "agent_question_resolved"; id: string; runId: string }
  | { type: "agent_question_error"; id: string; error: string };

/** Validate model-produced input rather than silently dropping questions. */
export function parseAgentQuestions(value: unknown): AgentQuestionRequest {
  const questions = (value as AgentQuestionRequest | undefined)?.questions;
  if (!Array.isArray(questions) || questions.length < 1 || questions.length > 3) {
    throw new Error("Ask between one and three questions at a time.");
  }
  const ids = new Set<string>();
  return { questions: questions.map((question) => {
    if (!question || typeof question !== "object") throw new Error("Invalid question.");
    const id = requiredText(question.id, 100);
    if (ids.has(id)) throw new Error("Question IDs must be unique.");
    ids.add(id);
    const options = question.options == null ? undefined : question.options;
    if (options && (!Array.isArray(options) || options.length > 6)) throw new Error("Use at most six options.");
    return {
      id,
      header: requiredText(question.header || "Clarification", 100),
      question: requiredText(question.question, 4000),
      isSecret: question.isSecret === true,
      options: options?.map((option) => ({
        label: requiredText(option?.label, 500),
        description: option?.description ? requiredText(option.description, 2000) : undefined,
      })),
    };
  }) };
}

export function validateAnswers(request: AgentQuestionRequest, input: unknown): AgentQuestionAnswers {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Answer each question before continuing.");
  const answers = input as AgentQuestionAnswers;
  const result: AgentQuestionAnswers = Object.create(null);
  for (const question of request.questions) {
    const values = Object.hasOwn(answers, question.id) ? answers[question.id]?.answers : undefined;
    if (!Array.isArray(values) || values.length !== 1) throw new Error("Answer each question before continuing.");
    result[question.id] = { answers: [requiredText(values[0], 16_000)] };
  }
  return result;
}

function requiredText(value: unknown, limit: number): string {
  if (typeof value !== "string" || !value.trim() || value.length > limit) throw new Error("Question or answer is missing or too long.");
  return value.trim();
}

export const ASK_USER_TOOL = {
  name: "detach_ask_user",
  description: "Ask the user for missing information or a decision and wait for their answer before continuing this task. Use when ambiguity materially changes the work; continue on your own for routine implementation choices. Never ask for passwords or tokens.",
  inputSchema: {
    type: "object", required: ["questions"],
    properties: { questions: {
      type: "array", minItems: 1, maxItems: 3,
      items: {
        type: "object", required: ["id", "header", "question"],
        properties: {
          id: { type: "string" }, header: { type: "string" }, question: { type: "string" },
          options: { type: "array", maxItems: 6, items: {
            type: "object", required: ["label"], properties: {
              label: { type: "string" }, description: { type: "string" },
            },
          } },
        },
      },
    } },
  },
};
