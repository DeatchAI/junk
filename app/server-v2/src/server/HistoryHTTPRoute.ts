import type { NativeHistoryService } from "../history/native/NativeHistoryService";

const response = (body: unknown, status = 200) => Response.json(body, {
  status, headers: { "Cache-Control": "no-store" },
});

function readError(req: Request) {
  // RuntimeServer checks the per-launch bearer token before dispatching here.
  if (req.headers.has("origin")) return response({ error: "Browser history access is not allowed." }, 403);
  if (req.method !== "GET") return response({ error: "Use GET to read conversation history." }, 405);
}

/** Bulk transcripts use HTTP, not the size-limited live-agent WebSocket. */
export async function historyConversationResponse(req: Request, url: URL, history: Pick<NativeHistoryService, "get">) {
  const failure = readError(req); if (failure) return failure;
  const id = url.searchParams.get("id");
  if (!id?.trim() || id.length > 512) return response({ error: "A valid conversation ID is required." }, 400);
  try {
    const entry = await history.get(id);
    if (!entry) return response({ error: "Conversation is unavailable. Refresh provider history." }, 404);
    return response({ type: "conversation", ...entry });
  } catch (error) {
    return response({ error: error instanceof Error ? error.message : "Provider history is unavailable." }, 503);
  }
}

/** Independent, read-only catalog/search for the composer's conversation picker. */
export function historyCatalogResponse(req: Request, url: URL, history: Pick<NativeHistoryService, "list" | "search">) {
  const failure = readError(req); if (failure) return failure;
  const query = (url.searchParams.get("query") ?? "").trim();
  const limit = Number(url.searchParams.get("limit") ?? "50");
  const offset = Number(url.searchParams.get("offset") ?? "0");
  if (query.length > 512 || !Number.isSafeInteger(limit) || limit < 1 || limit > 100
    || !Number.isSafeInteger(offset) || offset < 0 || offset > 10_000_000) {
    return response({ error: "Invalid conversation search or pagination." }, 400);
  }
  try {
    if (query) return response({ conversations: history.search(query, 100), offset: 0, hasMore: false });
    return response(history.list(limit, offset));
  } catch (error) {
    return response({ error: error instanceof Error ? error.message : "Provider history is unavailable." }, 503);
  }
}
