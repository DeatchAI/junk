import { expect, test } from "bun:test";
import { conversationPage } from "./ConversationPage";
import type { SqliteHistory } from "./SqliteHistory";

test("history pages expose older chats without duplicates or an unbounded query", () => {
  const data = Array.from({ length: 502 }, (_, index) => ({ id: String(index), created_at: index, updated_at: index }));
  const calls: number[][] = [];
  const history = { list(limit: number, offset: number) { calls.push([limit, offset]); return data.slice(offset, offset + limit); } } as SqliteHistory;
  const first = conversationPage(history);
  expect(first.conversations).toHaveLength(500); expect(first.hasMore).toBe(true);
  const second = conversationPage(history, 500, 500);
  expect(second.conversations.map((entry) => entry.id)).toEqual(["500", "501"]); expect(second.hasMore).toBe(false);
  conversationPage(history, Infinity, -10);
  expect(calls.at(-1)).toEqual([501, 0]);
});
