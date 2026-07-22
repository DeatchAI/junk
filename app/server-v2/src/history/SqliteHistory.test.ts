import { describe, expect, test } from "bun:test";

import { SqliteHistory } from "./SqliteHistory";

describe("conversation MCP memory", () => {
  test("remembers unique MCP server ids for a conversation", () => {
    const history = new SqliteHistory(":memory:");
    const { conversation } = history.addUserMessage(undefined, "Use GitHub for this task");

    history.mergeMCPServerIds(conversation.id, ["github", "github", "detach-browser-tools", ""]);

    expect(history.getMCPServerIds(conversation.id)).toEqual(["github", "detach-browser-tools"]);
  });

  test("removes remembered MCP ids when a conversation is deleted", () => {
    const history = new SqliteHistory(":memory:");
    const { conversation } = history.addUserMessage(undefined, "Temporary chat");

    history.mergeMCPServerIds(conversation.id, ["github"]);
    history.deleteConversation(conversation.id);

    expect(history.getMCPServerIds(conversation.id)).toEqual([]);
  });
});
