import { createInterface } from "node:readline";
const send = (value: unknown) => process.stdout.write(JSON.stringify(value) + "\n");
let loaded = false; let blocked = false; let loadID: number;
for await (const line of createInterface({ input: process.stdin })) {
  const frame = JSON.parse(line);
  if (frame.method === "initialize") send({ id: frame.id, result: { protocolVersion: 1, agentCapabilities: { loadSession: !process.argv.includes("--unsupported") } } });
  else if (frame.method === "session/new") throw new Error("Imported sessions must not start fresh.");
  else if (frame.method === "session/load") {
    if (frame.params.sessionId !== "saved-session") throw new Error("Wrong session.");
    loaded = true; loadID = frame.id;
    send({ method: "session/update", params: { sessionId: "saved-session", update: {
      sessionUpdate: "agent_message_chunk", content: { type: "text", text: "Old response, already imported" },
    } } });
    send({ id: 999, method: "session/request_permission", params: { sessionId: "saved-session", toolCall: { title: "Must not execute during replay" }, options: [{ optionId: "yes", kind: "allow_once" }] } });
  } else if (frame.id === 999) {
    blocked = frame.result.outcome.outcome === "cancelled";
    if (!blocked) throw new Error("Replay tried to execute a tool.");
    send({ id: loadID!, result: {} });
  } else if (frame.method === "session/prompt") {
    if (!loaded || !blocked) throw new Error("Resume did not finish safely.");
    send({ method: "session/update", params: { sessionId: "saved-session", update: {
      sessionUpdate: "agent_message_chunk", content: { type: "text", text: "New response only" },
    } } });
    send({ id: frame.id, result: { stopReason: "end_turn" } });
  }
}
