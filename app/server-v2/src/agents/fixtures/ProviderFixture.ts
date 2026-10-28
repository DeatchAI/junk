#!/usr/bin/env bun
// Real subprocess fixture. No provider, network, account, or model is contacted.
const args = process.argv.slice(2);
const mode = args.includes("acp") ? "omp" : args.includes("--execute") ? "amp" : "pi";
function send(value: unknown) { process.stdout.write(JSON.stringify(value) + "\n"); }
const option = (name: string) => args[args.indexOf(name) + 1];

if (mode === "amp") {
  const prompt = await Bun.stdin.text();
  const configPath = args.includes("--mcp-config") ? option("--mcp-config") : undefined;
  const config = configPath ? await Bun.file(configPath).json() : {};
  const text = JSON.stringify({ prompt, mode: args.includes("--mode") ? option("--mode") : null,
    cwd: process.cwd(), mcp: Object.keys(config) });
  send({ type: "system", subtype: "init", session_id: "T-amp-fixture" });
  send({ type: "assistant", message: { id: "a", content: [{ type: "text", text }] }, parent_tool_use_id: null });
  send({ type: "result", subtype: "success", is_error: false, result: text });
  process.exit(0);
}

let buffer = "", marker = "", sentPrompt = false, answered = false;
let modelSet = false, effortSet = false;
let permissionReplies = 0, allApproved = true;
if (args.includes("--extension")) {
  const extension = await import(option("--extension")!);
  extension.default({
    registerMcpServer() {}, registerCommand(name: string) { marker = name; }, on() {},
  });
}
for await (const chunk of Bun.stdin.stream()) {
  buffer += new TextDecoder().decode(chunk);
  let newline: number;
  while ((newline = buffer.indexOf("\n")) >= 0) {
    const raw = buffer.slice(0, newline); buffer = buffer.slice(newline + 1);
    if (!raw.trim()) continue;
    const frame = JSON.parse(raw);
    if (mode === "omp") {
      const result = (value: unknown) => send({ jsonrpc: "2.0", id: frame.id, result: value });
      if (frame.method === "initialize") result({ protocolVersion: 1 });
      else if (frame.method === "session/new") result({
        sessionId: "omp-fixture", configOptions: [
          { id: "model", category: "model", currentValue: "provider/default",
            options: [{ value: "provider/default", name: "Default model" }, { value: "provider/selected", name: "Selected model" }] },
          { id: "thinking", category: "thought_level", options: [{ value: "high", name: "High" }] },
        ],
      });
      else if (frame.method === "session/set_config_option") {
        if (frame.params.configId === "model") modelSet = frame.params.value === "provider/selected";
        if (frame.params.configId === "thinking") effortSet = frame.params.value === "high";
        result({ configOptions: [] });
      } else if (frame.method === "session/prompt") {
        for (const id of [900, 901]) send({ jsonrpc: "2.0", id, method: "session/request_permission", params: {
          sessionId: "omp-fixture", toolCall: { title: "Run tests", rawInput: { command: "bun test" } },
          options: [{ optionId: "allow", kind: "allow_once" }, { optionId: "deny", kind: "reject_once" }],
        } });
        marker = String(frame.id);
      } else if (frame.id === 900 || frame.id === 901) {
        permissionReplies += 1;
        allApproved = allApproved && frame.result.outcome.optionId === "allow";
        if (permissionReplies < 2) continue;
        if (allApproved) {
          send({ jsonrpc: "2.0", method: "session/update", params: {
            sessionId: "omp-fixture", update: { sessionUpdate: "agent_message_chunk",
              content: { type: "text", text: JSON.stringify({ modelSet, effortSet }) } },
          } });
          send({ jsonrpc: "2.0", id: Number(marker), result: { stopReason: "end_turn" } });
        } else send({ jsonrpc: "2.0", id: Number(marker), result: { stopReason: "refusal" } });
      }
      continue;
    }
    if (frame.type === "get_commands") send({ type: "response", id: frame.id, success: true, data: { commands: [{ name: marker }] } });
    else if (frame.type === "get_available_models") send({ type: "response", id: frame.id, success: true,
      data: { models: [{ provider: "provider", id: "default", name: "Default model" }] } });
    else if (frame.type === "get_state") send({ type: "response", id: frame.id, success: true,
      data: { model: { provider: "provider", id: "default" }, sessionId: "pi-fixture", sessionFile: "/tmp/pi-fixture.jsonl" } });
    else if (frame.type === "prompt") {
      sentPrompt = true;
      send({ type: "response", id: frame.id, success: true, data: { disposition: "started" } });
      send({ type: "message_start", message: { role: "assistant" } });
      send({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "Hello\u2028" } });
      send({ type: "agent_end", willRetry: true });
      send({ type: "extension_ui_request", id: "question", method: "select", title: "Which project?", options: ["Mac app", "Website"] });
      send({ type: "extension_ui_request", id: "permission", method: "confirm", title: "Allow command?", message: "bun test" });
    } else if (frame.type === "extension_ui_response" && frame.id === "question") {
      answered = frame.value === "Mac app";
    } else if (frame.type === "extension_ui_response" && frame.id === "permission") {
      if (frame.confirmed !== true || !answered || !sentPrompt) {
        send({ type: "message_end", message: { role: "assistant", stopReason: "error", errorMessage: "Denied" } });
      } else {
        send({ type: "message_update", assistantMessageEvent: { type: "text_delta", delta: "world" } });
        send({ type: "message_end", message: { role: "assistant", content: [{ type: "text", text: "Hello\u2028world" }] } });
        send({ type: "agent_settled", aborted: false });
      }
    }
  }
}
