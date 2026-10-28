import { expect, test } from "bun:test";
import { historyCacheResponse } from "./HistoryCacheRoute";

test("cache settings reject browser requests and invalid mutations without changing data", async () => {
  const calls: unknown[] = [];
  const history = {
    cacheStatus: { enabled: true, cachedChats: 1, cachedMessages: 2, bytes: 40 },
    configureSearchCache(enabled: boolean) { calls.push(enabled); }, clearSearchCache() { calls.push("clear"); },
  };
  function request(method: string, body?: unknown, origin?: string) {
    return historyCacheResponse(new Request("http://127.0.0.1/api/history/cache", {
      method, headers: { ...(origin ? { origin } : {}), "content-type": "application/json" },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    }), history);
  }
  expect((await request("GET", undefined, "null")).status).toBe(403);
  expect((await request("DELETE")).status).toBe(405);
  for (const body of [{}, null, [], { enabled: "false" }, { clear: false }, { deleteProviderHistory: true }]) {
    expect((await request("POST", body)).status).toBe(400);
  }
  expect(calls).toEqual([]);
  const get = await request("GET");
  expect(get.headers.get("cache-control")).toBe("no-store");
  expect(await get.json()).toEqual(history.cacheStatus);
  expect((await request("POST", { enabled: false })).status).toBe(200);
  expect((await request("POST", { clear: true })).status).toBe(200);
  expect(calls).toEqual([false, "clear"]);
});
