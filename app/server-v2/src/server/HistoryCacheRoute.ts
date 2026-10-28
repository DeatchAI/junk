import type { NativeHistoryService } from "../history/native/NativeHistoryService";

type Cache = Pick<NativeHistoryService, "cacheStatus" | "configureSearchCache" | "clearSearchCache">;

/** RuntimeServer authenticates the app's per-launch bearer token before dispatch. */
export async function historyCacheResponse(request: Request, history: Cache) {
  const reply = (body: unknown, status = 200) => Response.json(body, {
    status, headers: { "Cache-Control": "no-store" },
  });
  if (request.headers.has("origin")) return reply({ error: "Browser cache access is not allowed." }, 403);
  if (request.method === "GET") return reply(history.cacheStatus);
  if (request.method !== "POST") return reply({ error: "Use GET or POST for local cache settings." }, 405);
  try {
    const value: unknown = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) return reply({ error: "Invalid cache settings." }, 400);
    const body = value as Record<string, unknown>;
    if (!body || typeof body !== "object" || Array.isArray(body)
      || Object.keys(body).some((key) => !["enabled", "clear"].includes(key))
      || (body.enabled !== undefined && typeof body.enabled !== "boolean")
      || (body.clear !== undefined && body.clear !== true)
      || (body.enabled === undefined && body.clear !== true)) return reply({ error: "Invalid cache settings." }, 400);
    if (body.enabled !== undefined) history.configureSearchCache(body.enabled);
    if (body.clear === true) history.clearSearchCache();
    return reply(history.cacheStatus);
  } catch {
    return reply({ error: "Could not update Detach's local search cache." }, 400);
  }
}
