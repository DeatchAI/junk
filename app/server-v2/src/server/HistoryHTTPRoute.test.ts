import { expect, test } from "bun:test";
import { historyCatalogResponse, historyConversationResponse } from "./HistoryHTTPRoute";
import type { NativeHistoryService } from "../history/native/NativeHistoryService";

const entry = {
  conversation: { id: "native_fixture", title: "Large history", created_at: 1, updated_at: 2 },
  messages: [{ id: "m", conversation_id: "native_fixture", role: "assistant" as const,
    content: "🙂 Unicode history\n".repeat(150_000), created_at: 2 }],
};
const history: Pick<NativeHistoryService, "get"> = { async get(id) { return id === entry.conversation.id ? entry : undefined; } };
const request = (query: string, init?: RequestInit) => {
  const url = new URL(`http://127.0.0.1/api/history/conversation${query}`);
  return historyConversationResponse(new Request(url.toString(), init), url, history);
};

test("HTTP returns complete multi-megabyte histories without caching or truncating", async () => {
  const response = await request("?id=native_fixture");
  expect(response.status).toBe(200);
  expect(response.headers.get("cache-control")).toBe("no-store");
  const text = await response.text();
  expect(Buffer.byteLength(text)).toBeGreaterThan(1024 * 1024);
  expect(JSON.parse(text)).toEqual({ type: "conversation", ...entry });
});

test("invalid requests, browser origins, missing sessions and provider failures are isolated HTTP errors", async () => {
  expect((await request("")).status).toBe(400);
  expect((await request("?id=" + "x".repeat(513))).status).toBe(400);
  expect((await request("?id=native_fixture", { method: "POST" })).status).toBe(405);
  expect((await request("?id=native_fixture", { headers: { origin: "https://example.com" } })).status).toBe(403);
  expect((await request("?id=missing")).status).toBe(404);
  const url = new URL("http://127.0.0.1/api/history/conversation?id=broken");
  const response = await historyConversationResponse(new Request(url.toString()), url, { async get() { throw new Error("Provider offline"); } });
  expect(response.status).toBe(503);
  expect(await response.json()).toEqual({ error: "Provider offline" });
});

test("conversation picker pages and searches the same catalog without opening a chat", async () => {
  const calls: unknown[] = [];
  const catalog: Pick<NativeHistoryService, "list" | "search"> = {
    list(limit, offset) { calls.push([limit, offset]); return { conversations: [entry.conversation], offset: offset!, hasMore: true }; },
    search(query, limit) { calls.push([query, limit]); return [entry.conversation]; },
  };
  const listURL = new URL("http://127.0.0.1/api/history/conversations?limit=25&offset=50");
  const list = historyCatalogResponse(new Request(listURL.toString()), listURL, catalog);
  expect(list.status).toBe(200);
  expect(list.headers.get("cache-control")).toBe("no-store");
  expect(await list.json()).toEqual({ conversations: [entry.conversation], offset: 50, hasMore: true });
  const searchURL = new URL("http://127.0.0.1/api/history/conversations?query=%20Ink%20landing%20%F0%9F%99%82%20");
  const search = historyCatalogResponse(new Request(searchURL.toString()), searchURL, catalog);
  expect(await search.json()).toEqual({ conversations: [entry.conversation], offset: 0, hasMore: false });
  expect(calls).toEqual([[25, 50], ["Ink landing 🙂", 100]]);
});

test("conversation catalog rejects invalid inputs and browser access before reading history", async () => {
  const catalog: Pick<NativeHistoryService, "list" | "search"> = {
    list() { throw new Error("Offline"); }, search() { throw new Error("Offline"); },
  };
  function get(query = "", init?: RequestInit) {
    const url = new URL("http://127.0.0.1/api/history/conversations" + query);
    return historyCatalogResponse(new Request(url.toString(), init), url, catalog);
  }
  for (const invalid of ["?limit=0", "?limit=101", "?limit=1.5", "?offset=-1", "?offset=NaN", "?offset=1e12", "?query=" + "x".repeat(513)]) {
    expect(get(invalid).status).toBe(400);
  }
  expect(get("", { method: "POST" }).status).toBe(405);
  expect(get("", { headers: { origin: "null" } }).status).toBe(403);
  const offline = get();
  expect(offline.status).toBe(503);
  expect(await offline.json()).toEqual({ error: "Offline" });
  expect(get("?query=Ink").status).toBe(503);
});
