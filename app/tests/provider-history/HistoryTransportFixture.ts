import { historyCatalogResponse, historyConversationResponse } from "../../server-v2/src/server/HistoryHTTPRoute";
import { isAuthorizedRuntimeRequest } from "../../server-v2/src/runtime/RuntimeAuth";

const token = "isolated-history-transport-fixture";
const large = "Start\n" + "A🙂漢字\\\"\n".repeat(700_000) + "\nEND_OF_COMPLETE_HISTORY";
const entry = (id: string) => ({
  conversation: { id, title: id, created_at: 1, updated_at: 2, provider: "codex", origin: "provider", canResume: true },
  messages: [
    { id: "user", conversation_id: id, role: "user" as const, content: "Open saved task", created_at: 1 },
    { id: "assistant", conversation_id: id, role: "assistant" as const, content: id === "large" ? large : "Small saved answer", created_at: 2 },
  ],
});
const server = Bun.serve({
  port: 0, hostname: "127.0.0.1",
  async fetch(req, server) {
    const url = new URL(req.url);
    if (!isAuthorizedRuntimeRequest(req, url, token)) return Response.json({ error: "Unauthorized" }, { status: 401 });
    if (url.pathname === "/socket" && server.upgrade(req)) return;
    if (url.pathname === "/api/history/conversations") {
      return historyCatalogResponse(req, url, {
        list(_limit, offset = 0) { return { conversations: [entry("small").conversation], offset, hasMore: offset === 0 }; },
        search(query) { return query === "Ink & 🙂" ? [entry("small").conversation] : []; },
      });
    }
    return historyConversationResponse(req, url, { async get(id) {
      if (id === "slow") await Bun.sleep(500);
      if (id === "missing") return undefined;
      return entry(id);
    } });
  },
  websocket: { message(ws, raw) {
    const type = JSON.parse(String(raw)).type;
    ws.send(type === "large" ? JSON.stringify({ type: "conversation", ...entry("large") }) : JSON.stringify({ type: "pong" }));
  } },
});
await Bun.write(process.argv[2]!, JSON.stringify({ port: server.port, token }));
