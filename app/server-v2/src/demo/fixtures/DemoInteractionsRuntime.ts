import assert from "node:assert/strict";
import { createDemoRun, DEMO_TRIGGER_PROMPTS, matchDemoScenario } from "../DemoScenarios";
import { activeRuns, agentQuestions, pendingAgentPermissions, type ServerWebSocket } from "../../server/RuntimeContext";
import { requestAgentPermission, resolvePermissionsForRun } from "../../server/RuntimeApprovals";
import { handleMessage } from "../../server/RuntimeMessages";
import { clearQuestionWait, isWaitingForAnswer } from "../../questions/QuestionWait";

type Frame = { type: string; id?: string; runId?: string; command?: string; questions?: Array<{ id: string }> };
const frames: Frame[] = [];
const ws = { readyState: WebSocket.OPEN, send(raw: string) { frames.push(JSON.parse(raw)); return 1; } } as unknown as ServerWebSocket;

async function frame(type: string, from: number) {
  for (let i = 0; i < 100; i++) {
    const found = frames.slice(from).find((value) => value.type === type);
    if (found) return found;
    await Bun.sleep(2);
  }
  throw new Error("No real runtime " + type + " frame was emitted");
}

async function exercise(id: "approval" | "clarification", approved = true, cancel = false) {
  const runId = crypto.randomUUID(), conversationId = "demo_" + runId, from = frames.length;
  agentQuestions.registerRun(runId, { ws, conversationId, agent: "codex", taskTitle: "Demo interaction" });
  const run = createDemoRun(matchDemoScenario(DEMO_TRIGGER_PROMPTS[id], true)!, "codex", {
    onActivity() {}, onChunk() {},
    onPermission: (request) => requestAgentPermission(ws, request, runId, conversationId),
    onQuestion: (request) => agentQuestions.ask(runId, request),
  }, async () => {});
  activeRuns.set(ws, run);
  const outcome = run.finished.then((result) => ({ text: result.text, error: undefined }),
    (error: Error) => ({ text: "", error: error.message }));
  try {
    const request = await frame(id === "approval" ? "command_approval_request" : "agent_question", from);
    assert.equal(request.runId, runId);
    assert.equal(isWaitingForAnswer(runId), true);
    if (cancel) {
      await handleMessage(ws, JSON.stringify({ type: "stop_stream" }));
      assert.match((await outcome).error!, /Demo stopped/);
    } else if (id === "approval") {
      assert.equal(request.command, "demo.prepare_sample_report");
      await handleMessage(ws, JSON.stringify({ type: "command_approval_response", requestId: request.id, approved }));
      assert.match((await outcome).text, approved ? /You approved/ : /You denied/);
      assert.equal(frames.some((value) => value.id === request.id && value.type === "command_approval_resolved"), true);
    } else {
      const questionID = request.questions![0]!.id;
      await handleMessage(ws, JSON.stringify({ type: "agent_question_response",
        requestId: request.id, runId, answers: { [questionID]: { answers: ["Detailed"] } } }));
      assert.match((await outcome).text, /Report style: Detailed/);
      assert.equal(frames.some((value) => value.id === request.id && value.type === "agent_question_resolved"), true);
    }
    assert.equal(isWaitingForAnswer(runId), false);
    assert.equal([...pendingAgentPermissions.values()].some((value) => value.runId === runId), false);
  } finally {
    run.cancel();
    resolvePermissionsForRun(runId);
    agentQuestions.endRun(runId);
    activeRuns.delete(ws);
    clearQuestionWait(runId);
  }
}

await exercise("approval", true);
await exercise("approval", false);
await exercise("clarification");
await exercise("approval", true, true);
await exercise("clarification", true, true);
assert.equal(pendingAgentPermissions.size, 0);
console.log("Interactive demo approvals and clarifications round-trip through the real runtime handlers.");
process.exit(0);
