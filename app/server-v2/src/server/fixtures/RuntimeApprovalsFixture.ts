import assert from "node:assert/strict";
import { withTimeout } from "../../agents/CliAdapterUtils";
import { CodexAppServer } from "../../agents/codex/CodexAppServer";
import { withFixture } from "../../agents/codex/fixtures/CodexFixtureHarness";
import { beginQuestionWait, clearQuestionWait, isWaitingForAnswer } from "../../questions/QuestionWait";
import { pendingAgentPermissions, type ServerWebSocket } from "../RuntimeContext";
import { requestAgentPermission, resolveAgentPermission, resolvePermissionsForRun, resolvePermissionsForSocket } from "../RuntimeApprovals";

const permission = { title: "Run the requested command?", toolName: "printf fixture", description: "Fixture only", riskLevel: "normal" as const };
type Frame = { type: string; id: string; outcome?: string };
const realNow = Date.now;
const realTimeout = globalThis.setTimeout;
const sleep = (ms: number) => new Promise<void>((resolve) => realTimeout(resolve, ms));
const observe = (promise: Promise<boolean>): Promise<{ approved?: boolean; error?: Error }> =>
  promise.then((approved) => ({ approved }), (error) => ({ error }));

function socket(failSend = false) {
  const frames: Frame[] = [];
  const raw = { readyState: Number(WebSocket.OPEN), send(data: string) {
    if (failSend) throw new Error("Disconnected");
    frames.push(JSON.parse(data));
    return 1;
  } };
  return { raw, frames, ws: raw as unknown as ServerWebSocket };
}

function ask(client: ReturnType<typeof socket>, runId: string) {
  const result = observe(requestAgentPermission(client.ws, permission, runId, "chat-" + runId));
  return { id: client.frames.at(-1)!.id, result };
}

async function waitsIndefinitely() {
  const client = socket(), runId = "indefinite";
  // Accelerate the old approval expiry, while advancing the execution clock by two hours.
  globalThis.setTimeout = ((...args: Parameters<typeof setTimeout>) => {
    if (args[1] === 60_000) args[1] = 5;
    return realTimeout(...args);
  }) as typeof setTimeout;
  let settled = false, timeouts = 0;
  try {
    const request = requestAgentPermission(client.ws, permission, runId, "chat");
    const id = client.frames[0]!.id;
    const result = observe(withTimeout(request, 40, () => { timeouts++; }, runId));
    void result.then(() => { settled = true; });
    Date.now = () => realNow() + 2 * 60 * 60 * 1000;
    await sleep(350);
    assert.equal(settled, false, "An unanswered approval must never expire");
    assert.equal(timeouts, 0, "Human wait must pause the execution deadline");
    assert.equal(isWaitingForAnswer(runId), true);
    assert.equal(pendingAgentPermissions.has(id), true);
    assert.equal(client.frames.length, 1, "No automatic approval or denial may be sent");
    resolveAgentPermission(id, true);
    assert.deepEqual(await result, { approved: true });
    assert.equal(isWaitingForAnswer(runId), false);
    assert.equal(client.frames.at(-1)?.outcome, "approved");
  } finally {
    resolvePermissionsForRun(runId);
    Date.now = realNow;
    globalThis.setTimeout = realTimeout;
    clearQuestionWait(runId);
  }
}

async function independentRequests() {
  const first = socket(), second = socket();
  const one = ask(first, "shared"), two = ask(first, "shared"), other = ask(second, "other");
  const finishQuestion = beginQuestionWait("shared");
  resolveAgentPermission(one.id, true);
  assert.deepEqual(await one.result, { approved: true });
  assert.equal(isWaitingForAnswer("shared"), true, "Other interruptions must keep the agent on hold");
  resolveAgentPermission(one.id, false);
  assert.equal(first.frames.filter((frame) => frame.type === "command_approval_resolved").length, 1);
  resolveAgentPermission(two.id, false);
  assert.deepEqual(await two.result, { approved: false });
  assert.equal(isWaitingForAnswer("shared"), true, "A pending question must still hold execution");
  finishQuestion();
  assert.equal(isWaitingForAnswer("shared"), false);
  assert.equal(isWaitingForAnswer("other"), true);
  resolvePermissionsForSocket(second.ws, false);
  assert.match((await other.result).error!.message, /connection was lost/);
  assert.equal(second.frames.at(-1)?.outcome, "connection_lost");
  clearQuestionWait("shared");
  clearQuestionWait("other");
}

async function lifecycleCleanup() {
  const client = socket(), other = socket();
  const cancelled = ask(client, "cancelled"), retained = ask(client, "retained"), disconnected = ask(other, "disconnected");
  resolvePermissionsForRun("cancelled");
  assert.match((await cancelled.result).error!.message, /cancelled with the task/);
  assert.equal(isWaitingForAnswer("cancelled"), false);
  assert.equal(pendingAgentPermissions.has(retained.id), true);
  assert.equal(pendingAgentPermissions.has(disconnected.id), true);
  resolvePermissionsForSocket(client.ws, false, "cancelled");
  assert.match((await retained.result).error!.message, /cancelled with the task/);
  resolvePermissionsForSocket(other.ws, false);
  assert.match((await disconnected.result).error!.message, /connection was lost/);
  for (const runId of ["cancelled", "retained", "disconnected"]) clearQuestionWait(runId);
}

async function failedDelivery() {
  const closed = socket();
  closed.raw.readyState = WebSocket.CLOSED;
  const unavailable = await observe(requestAgentPermission(closed.ws, permission, "closed", "chat"));
  assert.match(unavailable.error!.message, /connection was lost/);
  const broken = socket(true);
  const undelivered = await observe(requestAgentPermission(broken.ws, permission, "broken", "chat"));
  assert.match(undelivered.error!.message, /connection was lost/);
  assert.equal(isWaitingForAnswer("closed"), false);
  assert.equal(isWaitingForAnswer("broken"), false);
  assert.equal(pendingAgentPermissions.size, 0);
  clearQuestionWait("closed");
  clearQuestionWait("broken");
}

async function approvalBeforeTurnAcknowledgement() {
  await withFixture("approval-before-start", async ({ executable, workspace, marker }) => {
    const client = socket(), runId = "codex-start-approval";
    const prompted = Promise.withResolvers<void>();
    const server = new CodexAppServer({ executable, cwd: workspace,
      request: { type: "chat", text: "Fixture", workspacePath: workspace, runId },
      callbacks: { onActivity() {}, onChunk() {}, onPermission(request) {
        const answer = requestAgentPermission(client.ws, request, runId, "chat");
        prompted.resolve();
        return answer;
      } },
    });
    let settled = false;
    const running = server.run("Fixture");
    void running.then(() => { settled = true; }, () => { settled = true; });
    try {
      await prompted.promise;
      Date.now = () => realNow() + 2 * 60 * 60 * 1000;
      await sleep(350);
      assert.equal(settled, false, "An approval must also pause an outstanding provider RPC");
      assert.equal(server.isAwaitingInput, true);
      assert.equal(await Bun.file(marker).exists(), false, "No command may execute without a decision");
      resolveAgentPermission(client.frames[0]!.id, true);
      assert.deepEqual(await running, { text: "Browser connected" });
      assert.equal(await Bun.file(marker).text(), "approved");
    } finally {
      server.cancel();
      resolvePermissionsForRun(runId);
      Date.now = realNow;
      clearQuestionWait(runId);
    }
  });
}

async function executionBudgetResumes() {
  const client = socket(), runId = "resume-budget";
  const approval = ask(client, runId);
  let timeouts = 0;
  const result = observe(withTimeout(new Promise<boolean>(() => {}), 40, () => { timeouts++; }, runId));
  await sleep(100);
  assert.equal(timeouts, 0);
  resolveAgentPermission(approval.id, true);
  assert.deepEqual(await approval.result, { approved: true });
  assert.match((await result).error!.message, /Agent did not finish/);
  assert.equal(timeouts, 1, "The normal execution deadline must resume after the response");
  clearQuestionWait(runId);
}

try {
  await waitsIndefinitely();
  await independentRequests();
  await lifecycleCleanup();
  await failedDelivery();
  await executionBudgetResumes();
  await approvalBeforeTurnAcknowledgement();
  assert.equal(pendingAgentPermissions.size, 0);
  console.log("Indefinite approvals, paused deadlines, explicit responses, and lifecycle cleanup passed");
  process.exit(0);
} catch (error) {
  console.error(error);
  process.exit(1);
}
