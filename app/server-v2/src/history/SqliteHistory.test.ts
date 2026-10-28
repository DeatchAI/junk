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

describe("historical message parts", () => {
  test("retains old opaque parts and text without calling a media provider", () => {
    const history = new SqliteHistory(":memory:");
    const { conversation } = history.addUserMessage(undefined, "An older conversation");
    const assistant = history.addAssistantMessage(conversation.id, "Saved response");
    history.updateMessageParts(assistant.id, "Saved response", [{ type: "media_job" }]);
    expect(history.get(conversation.id)?.messages[1]).toMatchObject({
      content: "Saved response", parts: [{ type: "media_job" }],
    });
  });
});
