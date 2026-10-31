import type { AgentActivityEvent } from "../protocol/messages";
import type { AgentStreamCallbacks } from "./AgentAdapter";
import { parseAgentQuestions } from "../questions/AgentQuestion";
import type { AgentQuestionRequest } from "../questions/AgentQuestion";
import { asStringRecord, getString } from "./CliAdapterUtils";

interface CursorACPMessage {
  id?: number;
  method?: string;
  params?: unknown;
}

type Reply = (id: number, response: { result?: unknown; error?: { code: number; message: string } }) => void;

export async function handleCursorACPMethod(message: CursorACPMessage, callbacks: AgentStreamCallbacks, reply: Reply) {
  const method = message.method;
  const params = asStringRecord(message.params) ?? {};
  if (method === "cursor/ask_question" && typeof message.id === "number") {
    reply(message.id, { result: await askQuestions(params, callbacks) });
  } else if (method === "cursor/create_plan" && typeof message.id === "number") {
    reply(message.id, { result: await approvePlan(params, callbacks) });
  } else if (method === "cursor/update_todos") {
    reportTodos(params, callbacks);
  } else if (method === "cursor/task") {
    const description = getString(params.description)?.trim();
    if (description) callbacks.onActivity(`Cursor subagent: ${description}`, "task");
  } else if (typeof message.id === "number") {
    reply(message.id, { error: { code: -32601, message: "Unsupported Cursor ACP extension method." } });
  }
}

async function askQuestions(params: Record<string, unknown>, callbacks: AgentStreamCallbacks) {
  const title = getString(params.title)?.trim().slice(0, 100) || "Cursor needs your input";
  const rawQuestions = Array.isArray(params.questions) ? params.questions : [];
  if (!callbacks.onQuestion || rawQuestions.length < 1 || rawQuestions.length > 3) return skippedQuestion();

  let request: AgentQuestionRequest;
  try {
    request = parseAgentQuestions({ questions: rawQuestions.map((value) => {
      const question = asStringRecord(value);
      const options = Array.isArray(question?.options) ? question.options : [];
      const id = getString(question?.id);
      if (!id || question?.allowMultiple === true || options.length < 1 || options.length > 6) {
        throw new Error("Unsupported Cursor question.");
      }
      return {
        id,
        header: title,
        question: getString(question?.prompt) || "Choose an option to continue.",
        options: options.map((value) => {
          const option = asStringRecord(value);
          const optionID = getString(option?.id), label = getString(option?.label);
          if (!optionID || !label) throw new Error("Cursor question choices need IDs and labels.");
          return { label, description: getString(option?.description) };
        }),
      };
    }) });
  } catch {
    return skippedQuestion();
  }

  const answers = await callbacks.onQuestion(request);
  if (!answers) return { outcome: { outcome: "cancelled" } };
  const selections = request.questions.map((question) => {
    const answer = answers[question.id]?.answers[0];
    const option = question.options?.find((candidate) => candidate.label === answer);
    const selectedOptionId = option ? optionId(rawQuestions, question.id, option.label) : undefined;
    return selectedOptionId ? { questionId: question.id, selectedOptionIds: [selectedOptionId] } : undefined;
  });
  if (selections.some((selection) => !selection)) return skippedQuestion("Choose one of Cursor's listed options to continue.");
  return { outcome: { outcome: "answered", answers: selections } };
}

async function approvePlan(params: Record<string, unknown>, callbacks: AgentStreamCallbacks) {
  if (!callbacks.onQuestion) return { outcome: { outcome: "rejected", reason: "Detach could not request plan approval." } };
  const plan = [getString(params.overview), getString(params.plan)].filter(Boolean).join("\n\n").slice(0, 4_000);
  const answer = await callbacks.onQuestion({ questions: [{
    id: "cursor-plan-approval",
    header: getString(params.name)?.slice(0, 100) || "Review Cursor's plan",
    question: `${plan || "Cursor wants to proceed with its plan."}\n\nApprove this plan?`,
    options: [{ label: "Approve" }, { label: "Decline" }],
  }] });
  const choice = answer?.["cursor-plan-approval"]?.answers[0];
  return choice === "Approve" ? { outcome: { outcome: "accepted" } }
    : answer ? { outcome: { outcome: "rejected", reason: "The user declined the plan." } }
    : { outcome: { outcome: "cancelled" } };
}

function reportTodos(params: Record<string, unknown>, callbacks: AgentStreamCallbacks) {
  const todos = Array.isArray(params.todos) ? params.todos : [];
  const items = todos.flatMap((value) => {
    const todo = asStringRecord(value);
    const status = getString(todo?.status);
    if (!todo || !status) return [];
    return [{ completed: status === "completed", status }];
  }).slice(0, 100);
  if (!items.length) return;
  const event: AgentActivityEvent = {
    agent: "cursor", kind: "plan", action: "plan", phase: "updated", title: "Cursor plan",
    userFacing: true, sourceEventType: "cursor.update_todos", details: { items },
  };
  callbacks.onActivity("Updating the plan", "plan", event);
}

function optionId(questions: unknown[], questionId: string, label: string) {
  const question = questions.map(asStringRecord).find((item) => item?.id === questionId);
  const option = (Array.isArray(question?.options) ? question.options : []).map(asStringRecord)
    .find((item) => item?.label === label);
  return getString(option?.id);
}

function skippedQuestion(reason = "Cursor's question could not be shown in Detach.") {
  return { outcome: { outcome: "skipped", reason } };
}
