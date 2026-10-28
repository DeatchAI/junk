import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { buildCodexAppServerArgs, buildCodexThreadParams, buildCodexTurnParams } from "./CodexConfiguration";
import { buildClaudeArgs } from "../ClaudeAdapter";
import { withFixture } from "./fixtures/CodexFixtureHarness";

describe("native permission configuration", () => {
  const request = { type: "chat" as const, text: "Inspect the app" };

  test("agent default leaves native sandbox and approval settings intact", () => {
    const args = buildCodexAppServerArgs().join(" ");
    expect(args).not.toContain("sandbox_mode");
    expect(args).not.toContain("approval_policy");
    const thread = buildCodexThreadParams(request, "/tmp/workspace");
    const turn = buildCodexTurnParams(request, "/tmp/workspace", "thread", request.text);
    expect(thread.sandbox).toBeUndefined();
    expect(thread).not.toHaveProperty("approvalPolicy");
    expect(turn.sandboxPolicy).toBeUndefined();
    expect(turn).not.toHaveProperty("approvalsReviewer");
  });

  test("Claude's explicit agent default opts out of a legacy Detach environment override", () => {
    const previous = Bun.env.DETACH_CLAUDE_PERMISSION_MODE;
    try {
      Bun.env.DETACH_CLAUDE_PERMISSION_MODE = "auto";
      expect(buildClaudeArgs(request.text, { ...request, permissionMode: "native" })).not.toContain("--permission-mode");
    } finally {
      if (previous === undefined) delete Bun.env.DETACH_CLAUDE_PERMISSION_MODE;
      else Bun.env.DETACH_CLAUDE_PERMISSION_MODE = previous;
    }
  });

  test.each(["supervised", "auto"] as const)("%s keeps the workspace sandbox and routes reviews explicitly", (mode) => {
    const selected = { ...request, permissionMode: mode };
    const turn = buildCodexTurnParams(selected, "/tmp/workspace", "thread", request.text);
    expect(turn.approvalsReviewer).toBe(mode === "auto" ? "auto_review" : "user");
    expect(turn.approvalPolicy).toBe("on-request");
    expect(turn.sandboxPolicy).toMatchObject({ type: "workspaceWrite", networkAccess: false });
    expect(buildClaudeArgs(request.text, selected)).toContain(mode === "auto" ? "auto" : "default");
  });
});

test("a resumed native session receives raw user input with separate selected context", async () => {
  await withFixture("stream", async ({ adapter, workspace, log }) => {
    const text = "Polish the activity panel.";
    await adapter.run({ type: "chat", text, workspacePath: workspace, providerSessionId: "imported-thread",
      systemPrompt: "Use the selected checklist.", attachmentContext: "User-selected reference text." }, {
      onActivity() {}, onChunk() {},
    }).finished;
    const messages = (await readFile(log, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
    expect(messages.find((message) => message.method === "thread/resume").params.threadId).toBe("imported-thread");
    const turn = messages.find((message) => message.method === "turn/start").params;
    expect(turn.input).toEqual([{ type: "text", text, text_elements: [] }]);
    expect(turn.additionalContext).toEqual({
      "detach.selected-instructions": { kind: "application", value: "Use the selected checklist." },
      "detach.attachments": { kind: "untrusted", value: "User-selected reference text." },
    });
  });
});
