import type { SqliteHistory } from "./SqliteHistory";

export function conversationPage(history: SqliteHistory, limit = 500, offset = 0) {
  limit = Number.isFinite(limit) ? Math.max(1, Math.min(500, Math.trunc(limit))) : 500;
  offset = Number.isFinite(offset) ? Math.max(0, Math.trunc(offset)) : 0;
  const conversations = history.list(limit + 1, offset);
  return { conversations: conversations.slice(0, limit), offset, hasMore: conversations.length > limit };
}
