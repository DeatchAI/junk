import { tmpdir } from "node:os";
const send = (value: unknown) => process.stdout.write(JSON.stringify(value) + "\n");
let buffer = "", loading: number | undefined;
for await (const chunk of Bun.stdin.stream()) {
  buffer += new TextDecoder().decode(chunk);
  let end: number;
  while ((end = buffer.indexOf("\n")) !== -1) {
    const frame = JSON.parse(buffer.slice(0, end)); buffer = buffer.slice(end + 1);
    const result = (value: unknown) => send({ jsonrpc: "2.0", id: frame.id, result: value });
    if (frame.method === "initialize") result({ protocolVersion: 1, agentCapabilities: {
      loadSession: true, sessionCapabilities: Bun.env.HISTORY_FIXTURE_UNSUPPORTED ? {} : { list: {} },
    } });
    else if (frame.method === "session/list") result({ sessions: [{ sessionId: "saved-session", title: "Saved ACP task",
      cwd: tmpdir(), createdAt: "2026-09-01T00:00:00Z", updatedAt: "2026-09-01T00:01:00Z" }] });
    else if (frame.method === "session/load") {
      loading = frame.id;
      const update = (value: unknown) => send({ jsonrpc: "2.0", method: "session/update", params: { sessionId: "saved-session", update: value } });
      update({ sessionUpdate: "user_message_chunk", content: { type: "text", text: "Saved prompt" } });
      update({ sessionUpdate: "tool_call", toolCallId: "tool", title: "Run tests" });
      update({ sessionUpdate: "tool_call_update", toolCallId: "tool", content: [{ type: "content", content: { type: "text", text: "Historical test output" } }] });
      update({ sessionUpdate: "agent_message_chunk", content: { type: "text", text: "Token" } });
      update({ sessionUpdate: "agent_message_chunk", content: { type: "text", text: "-joined answer" } });
      send({ jsonrpc: "2.0", id: 900, method: "session/request_permission", params: { sessionId: "saved-session" } });
    } else if (frame.id === 900) {
      if (frame.result?.outcome?.outcome !== "cancelled") throw new Error("History reader granted permission");
      send({ jsonrpc: "2.0", id: loading, result: {} });
    } else throw new Error(`History scan attempted a forbidden method: ${frame.method}`);
  }
}
