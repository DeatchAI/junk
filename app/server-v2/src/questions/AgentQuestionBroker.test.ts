import { describe, expect, test } from "bun:test";
import { AgentQuestionBroker } from "./AgentQuestionBroker";
import type { AgentQuestionServerMessage } from "./AgentQuestion";
import { beginQuestionWait, clearQuestionWait, isWaitingForAnswer } from "./QuestionWait";
import { withTimeout } from "../agents/CliAdapterUtils";

const request = { questions: [{ id: "scope", header: "Scope", question: "Which project?",
  options: [{ label: "Website" }, { label: "Mac app" }] }] };
const answers = { scope: { answers: ["My custom project"] } };

function setup() {
  const events: Array<{ ws: object; message: AgentQuestionServerMessage }> = [];
  const remembered: string[] = [];
  const broker = new AgentQuestionBroker<object>((ws, message) => events.push({ ws, message }), (_, text) => remembered.push(text));
  return { broker, events, remembered };
}

describe("provider-neutral clarification", () => {
  test.each(["codex", "claude", "grok", "opencode", "fx", "pi", "amp", "omp"])("pauses %s until the originating user replies", async (agent) => {
    const { broker, events, remembered } = setup();
    const ws = {};
    const runId = `run-${agent}`;
    broker.registerRun(runId, { ws, conversationId: "chat", agent });
    let finished = false;
    const waiting = broker.ask(runId, request).then((value) => { finished = true; return value; });
    await Promise.resolve();
    expect(finished).toBe(false);
    expect(isWaitingForAnswer(runId)).toBe(true);
    const question = events[0]!.message;
    expect(question.type).toBe("agent_question");
    const id = (question as { id: string }).id;
    expect(broker.respond({}, { type: "agent_question_response", requestId: id, runId, answers })).toBe(false);
    expect(broker.respond(ws, { type: "agent_question_response", requestId: id, runId: "other-run", answers })).toBe(false);
    expect(finished).toBe(false);
    expect(broker.respond(ws, { type: "agent_question_response", requestId: id, runId, answers })).toBe(true);
    expect(await waiting).toEqual(answers);
    expect(isWaitingForAnswer(runId)).toBe(false);
    expect(remembered).toEqual(["Clarification:\nWhich project?\nMy custom project"]);
    expect(broker.respond(ws, { type: "agent_question_response", requestId: id, runId, answers })).toBe(false);
    broker.endRun(runId);
  });

  test("retains an unanswered question after an incomplete or blank reply", async () => {
    const { broker, events } = setup();
    const ws = {};
    broker.registerRun("incomplete", { ws, conversationId: "chat", agent: "pi" });
    const waiting = broker.ask("incomplete", request);
    const id = (events[0]!.message as { id: string }).id;
    expect(broker.respond(ws, { type: "agent_question_response", requestId: id, runId: "incomplete",
      answers: { scope: { answers: [" "] } } })).toBe(false);
    expect(events.at(-1)?.message.type).toBe("agent_question_error");
    expect(isWaitingForAnswer("incomplete")).toBe(true);
    broker.endRun("incomplete");
    expect(await waiting).toBeNull();
  });

  test("keeps simultaneous agents isolated and clears only the disconnected task", async () => {
    const { broker, events } = setup();
    const first = {}, second = {};
    broker.registerRun("first", { ws: first, conversationId: "one", agent: "claude" });
    broker.registerRun("second", { ws: second, conversationId: "two", agent: "amp" });
    const one = broker.ask("first", request), two = broker.ask("second", request);
    broker.endSocket(first);
    expect(await one).toBeNull();
    expect(isWaitingForAnswer("second")).toBe(true);
    const id = (events.find((item) => item.ws === second)!.message as { id: string }).id;
    broker.respond(second, { type: "agent_question_response", requestId: id, runId: "second", answers });
    expect(await two).toEqual(answers);
    broker.endSocket(second);
  });

  test("never saves secret answers to conversation history", async () => {
    const { broker, events, remembered } = setup();
    const ws = {};
    broker.registerRun("secret", { ws, conversationId: "chat", agent: "codex" });
    const waiting = broker.ask("secret", { questions: [{ ...request.questions[0], isSecret: true }] });
    broker.respond(ws, { type: "agent_question_response", requestId: (events[0]!.message as { id: string }).id, runId: "secret", answers });
    await waiting;
    expect(remembered).toEqual([]);
    broker.endRun("secret");
  });

  test("rejects questions from finished or unknown tasks", async () => {
    const { broker } = setup();
    await expect(broker.ask("unknown", request)).rejects.toThrow("active Detach task");
  });

  test("waiting for a human does not consume the agent execution deadline", async () => {
    const runId = "deadline";
    const finishWait = beginQuestionWait(runId);
    let timedOut = false;
    const result = Promise.withResolvers<string>();
    const running = withTimeout(result.promise, 40, () => { timedOut = true; }, runId);
    try {
      await Bun.sleep(100);
      expect(timedOut).toBe(false);
      finishWait();
      result.resolve("continued");
      expect(await running).toBe("continued");
    } finally { finishWait(); clearQuestionWait(runId); }
  });
});
