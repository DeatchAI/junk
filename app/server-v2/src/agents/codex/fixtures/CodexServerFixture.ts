import { appendFileSync, writeFileSync } from "node:fs";
import { createInterface } from "node:readline";

export async function runCodexFixture(options: { mode: string; marker: string; log: string }) {
  const approvalReplies: string[] = [];
  const send = (message: unknown) => process.stdout.write(`${JSON.stringify(message)}\n`);
  let threadId = "thread-test";
  let deferredTurnStartID: number | undefined;
  const notify = (method: string, params: Record<string, unknown>) => send({ method, params: { threadId, ...params } });
  const finish = (text: string) => {
    notify("item/agentMessage/delta", { itemId: "reply", delta: text.slice(0, 4) });
    notify("item/agentMessage/delta", { itemId: "reply", delta: text.slice(4) });
    notify("item/completed", { item: { type: "agentMessage", id: "reply", text } });
    notify("turn/completed", { turn: { id: "turn-test", status: "completed" } });
  };
  const lines = createInterface({ input: process.stdin });
  for await (const line of lines) {
    const message = JSON.parse(line);
    appendFileSync(options.log, `${JSON.stringify(message)}\n`);
    if (message.method === "initialize") {
      if (message.params?.clientInfo?.name !== "detach") throw new Error("Missing Detach client identity");
      if (options.mode.startsWith("question") && !message.params.capabilities?.experimentalApi) throw new Error("Question protocol was not enabled");
      send({ id: message.id, result: { userAgent: "test-server" } });
    } else if (message.method === "thread/fork") {
      if (message.params.threadId !== "imported-thread" || (options.mode === "fork-after" ? message.params.beforeTurnId !== undefined : message.params.beforeTurnId !== "turn-replaced")) {
        throw new Error("Missing exact native branch boundary");
      }
      threadId = "fork-test";
      send({ id: message.id, result: { thread: { id: threadId, forkedFromId: message.params.threadId } } });
    } else if (message.method === "thread/turns/list") {
      send({ id: message.id, result: { data: options.mode === "fork-empty" ? [] :
        [{ id: options.mode === "fork-invalid" ? "turn-replaced" : options.mode === "fork-after" ? "turn-selected" : "turn-ancestor" }] } });
    } else if (message.method === "thread/archive") {
      writeFileSync(options.marker, "archived");
      send({ id: message.id, result: {} });
    } else if (message.method === "thread/start" || message.method === "thread/resume") {
      if (message.params.approvalPolicy && (message.params.sandbox !== "workspace-write"
        || message.params.approvalPolicy !== "on-request"
        || !["user", "auto_review"].includes(message.params.approvalsReviewer))) {
        throw new Error("Unexpected explicit approval policy");
      }
      if (message.method === "thread/resume" && (message.params.threadId !== "imported-thread" || !message.params.excludeTurns)) {
        throw new Error("Missing imported thread identity");
      }
      if (message.method === "thread/resume") threadId = message.params.threadId;
      send({ id: message.id, result: { thread: { id: threadId } } });
    } else if (message.method === "turn/start") {
      if (message.params.sandboxPolicy && (message.params.sandboxPolicy.networkAccess !== false || message.params.sandboxPolicy.type !== "workspaceWrite")) {
        throw new Error("Unexpected broad permissions");
      }
      if (options.mode === "crash") process.exit(2);
      if (options.mode === "approval-before-start") deferredTurnStartID = message.id;
      else send({ id: message.id, result: { turn: { id: "turn-test" } } });
      notify("turn/started", { turn: { id: "turn-test" } });
      if (options.mode === "fork-stalled" || options.mode === "startup-stalled") continue;
      if (options.mode === "fork-thinking") {
        notify("item/started", { turnId: "turn-test", item: { id: "thinking", type: "reasoning" } });
        setTimeout(() => finish("Independent branch reply"), 140);
        continue;
      }
      if (options.mode.startsWith("fork")) { finish("Independent branch reply"); continue; }
      if (options.mode.startsWith("question")) {
        if (!process.argv.includes("features.default_mode_request_user_input=true")) throw new Error("Default-mode questions were not enabled");
        send({ id: "question-1", method: options.mode === "question-legacy" ? "tool/requestUserInput" : "item/tool/requestUserInput", params: {
          threadId: options.mode === "question-foreign" ? "other-thread" : threadId,
          turnId: "turn-test", itemId: "question-item", isBlocking: true,
          questions: [
            { id: "project", header: "Project", question: "Which project should I update?", options: [{ label: "Website", description: "Update the web app" }] },
            { id: "detail", header: "Details", question: "What should change?", options: null },
          ],
        } });
        continue;
      }
      if (options.mode === "stream") {
        notify("item/agentMessage/delta", { itemId: "first", delta: "First message" });
        notify("item/completed", { item: { id: "first", type: "agentMessage", text: "First message" } });
        notify("item/completed", { item: { id: "second", type: "agentMessage", text: "Second message" } });
        notify("turn/completed", { turn: { id: "turn-test", status: "completed" } });
        continue;
      }
      if (options.mode === "parallel") {
        for (let index = 1; index <= 3; index++) {
          notify("item/started", { item: {
            id: `operation-${index}`, type: "commandExecution", status: "inProgress",
            command: `notch-browser check-${index} --json`,
          } });
          send({ id: `parallel-${index}`, method: "item/commandExecution/requestApproval", params: {
            threadId: "thread-test", turnId: "turn-test", itemId: `operation-${index}`,
            command: `notch-browser check-${index} --json`,
          } });
        }
        notify("item/agentMessage/delta", { itemId: "emitted", delta: "All requests emitted" });
        continue;
      }
      const item = options.mode === "file"
        ? { type: "fileChange", id: "operation", status: "inProgress", changes: [{ path: options.marker, kind: { type: "add" }, diff: "+approved" }] }
        : { type: "commandExecution", id: "operation", status: "inProgress", command: "notch-browser status --json" };
      notify("item/started", { item });
      const method = options.mode === "file" ? "item/fileChange/requestApproval"
        : options.mode === "permissions" ? "item/permissions/requestApproval" : "item/commandExecution/requestApproval";
      send({ id: "approval-1", method, params: {
        threadId: options.mode === "foreign" ? "other-thread" : threadId,
        turnId: "turn-test", itemId: "operation", command: "notch-browser status --json",
        reason: "Connect to Notch Browser", grantRoot: options.marker,
        permissions: { network: { enabled: true } },
      } });
    } else if (message.id === "question-1") {
      const answers = message.result?.answers;
      if (answers?.project?.answers?.length && answers?.detail?.answers?.length) {
        writeFileSync(options.marker, "answered");
        finish(`Updating ${answers.project.answers[0]}: ${answers.detail.answers[0]}`);
      } else { finish("Question cancelled"); }
    } else if (String(message.id).startsWith("parallel-")) {
      approvalReplies.push(`${message.id}:${message.result?.decision || "error"}`);
      if (message.result?.decision === "accept") {
        appendFileSync(options.marker, `${message.id}\n`);
      }
      if (approvalReplies.length === 3) finish("Approvals completed");
    } else if (message.id === "approval-1") {
      if (deferredTurnStartID !== undefined) {
        send({ id: deferredTurnStartID, result: { turn: { id: "turn-test" } } });
        deferredTurnStartID = undefined;
      }
      const allowed = message.result?.decision === "accept" || message.result?.permissions?.network?.enabled === true;
      if (allowed) writeFileSync(options.marker, "approved");
      notify("item/completed", { item: {
        id: "operation", type: "commandExecution", command: "notch-browser status --json",
        status: allowed ? "completed" : "declined", exitCode: allowed ? 0 : 1,
      } });
      finish(allowed ? "Browser connected" : "Permission denied");
    } else if (message.method === "turn/interrupt") {
      send({ id: message.id, result: {} });
      notify("turn/completed", { turn: { id: "turn-test", status: "interrupted" } });
    }
  }
}
