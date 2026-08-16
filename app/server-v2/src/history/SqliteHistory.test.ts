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

describe("conversation media parts", () => {
  test("persists and updates typed media jobs without markdown URLs", () => {
    const history = new SqliteHistory(":memory:");
    const { conversation } = history.addUserMessage(undefined, "Paint a paper fox");
    const job = {
      id: "job-1",
      kind: "image" as const,
      model: "gpt-image-2",
      state: "waiting",
      progress: 0,
      config: { aspectRatio: "1:1" },
      assets: [],
    };
    const assistant = history.addMediaMessage(
      conversation.id,
      "assistant",
      "Generating image…",
      [{ type: "media_job", job }],
    );

    history.updateMessageParts(
      assistant.id,
      "Generated an image.",
      [{
        type: "media_job",
        job: {
          ...job,
          state: "succeeded",
          progress: 100,
          assets: [{
            id: "asset-1",
            kind: "image",
            mimeType: "image/png",
            url: "https://storage.example/signed",
          }],
        },
      }],
    );

    const stored = history.get(conversation.id)?.messages[1];
    expect(stored?.content).toBe("Generated an image.");
    expect(stored?.parts?.[0]).toMatchObject({
      type: "media_job",
      job: { id: "job-1", state: "succeeded" },
    });
  });
});
