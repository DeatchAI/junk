import { expect, test } from "bun:test";
import { join } from "node:path";
import { CAPABILITY_MCP_TOOLS } from "../capabilities/CapabilityMCPServer";
import { AgentQuestionBroker } from "./AgentQuestionBroker";
import type { AgentQuestionServerMessage } from "./AgentQuestion";

test("any MCP harness can ask, pause, and continue through the shared question tool", async () => {
  expect(CAPABILITY_MCP_TOOLS.some((tool) => tool.name === "detach_ask_user")).toBe(true);
  const ws = {}, shown = Promise.withResolvers<Extract<AgentQuestionServerMessage, { type: "agent_question" }>>();
  const broker = new AgentQuestionBroker<object>((_, message) => {
    if (message.type === "agent_question") shown.resolve(message);
  });
  broker.registerRun("generic-run", { ws, conversationId: "chat", agent: "any-mcp-harness" });
  const server = Bun.serve({
    port: 0, hostname: "127.0.0.1",
    async fetch(request) {
      expect(request.headers.get("authorization")).toBe("Bearer test-runtime-token");
      const body = await request.json() as { runId: string };
      expect(body.runId).toBe("generic-run");
      const answers = await broker.ask(body.runId, body);
      return Response.json({ ok: true, result: { answers } });
    },
  });
  const child = Bun.spawn([process.execPath, "-e", `import {runCapabilityMCPServer} from ${JSON.stringify(join(import.meta.dir, "../capabilities/CapabilityMCPServer.ts"))}; await runCapabilityMCPServer();`], {
    env: { ...Bun.env, DETACH_RUNTIME_URL: server.url.href.replace(/\/$/, ""), DETACH_RUNTIME_TOKEN: "test-runtime-token", DETACH_CAPABILITY_RUN_ID: "generic-run" },
    stdin: "pipe", stdout: "pipe", stderr: "pipe",
  });
  try {
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/call", params: {
      name: "detach_ask_user", arguments: { questions: [{ id: "scope", header: "Scope", question: "Which project?" }] },
    } })}\n`);
    child.stdin.flush();
    const question = await shown.promise;
    const answers = { scope: { answers: ["My Mac app"] } };
    broker.respond(ws, { type: "agent_question_response", requestId: question.id, runId: "generic-run", answers });
    child.stdin.end();
    const output = await new Response(child.stdout).text();
    expect(await child.exited).toBe(0);
    const reply = JSON.parse(output.trim());
    expect(reply.id).toBe(1);
    expect(JSON.parse(reply.result.content[0].text).answers).toEqual(answers);
  } finally {
    broker.endRun("generic-run");
    child.kill();
    server.stop(true);
  }
});
