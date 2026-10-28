import { describe, expect, test } from "bun:test";
import { readFile } from "node:fs/promises";
import { withFixture } from "./fixtures/CodexFixtureHarness";
import type { AgentPermissionRequest, AgentStreamCallbacks } from "../AgentAdapter";

describe("Codex interactive permissions", () => {
  test("an expired approval fails with its reason instead of pretending the user declined", async () => {
    await withFixture("command", async ({ adapter, workspace, marker }) => {
      const run = adapter.run({ type: "chat", text: "Check the app", workspacePath: workspace }, {
        onActivity() {}, onChunk() {},
        async onPermission() { throw new Error("The approval request timed out without an answer."); },
      });
      await expect(run.finished).rejects.toThrow("timed out without an answer");
      expect(await Bun.file(marker).exists()).toBe(false);
    });
  });
  test("presents concurrent requests one at a time without replacing pending approvals", async () => {
    await withFixture("parallel", async ({ adapter, workspace, marker, log }) => {
      const emitted = Promise.withResolvers<void>();
      const firstPrompt = Promise.withResolvers<void>();
      const decision = Promise.withResolvers<boolean>();
      const requests: string[] = [];
      const run = adapter.run({ type: "chat", text: "Check the browser", workspacePath: workspace }, {
        onActivity() {}, onChunk(text) { if (text.includes("All requests emitted")) emitted.resolve(); },
        onPermission(request) {
          requests.push(request.toolName || "");
          if (requests.length === 1) { firstPrompt.resolve(); return decision.promise; }
          return Promise.resolve(requests.length === 3);
        },
      });
      try {
        await Promise.all([emitted.promise, firstPrompt.promise]);
        expect(requests).toEqual(["notch-browser check-1 --json"]);
        expect(await Bun.file(marker).exists()).toBe(false);
      } finally {
        decision.resolve(true);
        await run.finished;
      }
      expect(requests).toHaveLength(3);
      expect((await readFile(marker, "utf8")).trim().split("\n")).toEqual(["parallel-1", "parallel-3"]);
      const replies = (await readFile(log, "utf8")).trim().split("\n").map((line) => JSON.parse(line))
        .filter((message) => String(message.id).startsWith("parallel-"));
      expect(replies.map((reply) => reply.result.decision)).toEqual(["accept", "decline", "accept"]);
    });
  });

  test("discards queued requests when the task is cancelled", async () => {
    await withFixture("parallel", async ({ adapter, workspace, marker }) => {
      const emitted = Promise.withResolvers<void>();
      const waiting = Promise.withResolvers<void>();
      const decision = Promise.withResolvers<boolean>();
      let prompts = 0;
      const run = adapter.run({ type: "chat", text: "Check the browser", workspacePath: workspace }, {
        onActivity() {}, onChunk(text) { if (text.includes("All requests emitted")) emitted.resolve(); },
        onPermission() { prompts++; waiting.resolve(); return decision.promise; },
      });
      await Promise.all([emitted.promise, waiting.promise]);
      run.cancel();
      await run.finished;
      decision.resolve(true);
      expect(prompts).toBe(1);
      expect(await Bun.file(marker).exists()).toBe(false);
    });
  });

  test("pauses the command until Detach approves, then streams its result", async () => {
    await withFixture("command", async ({ adapter, workspace, marker, log }) => {
      const requests: AgentPermissionRequest[] = [];
      const chunks: string[] = [];
      const run = adapter.run({ type: "chat", text: "Check the browser", workspacePath: workspace }, {
        onActivity() {}, onChunk(text) { chunks.push(text); },
        async onPermission(request) {
          requests.push(request);
          expect(await Bun.file(marker).exists()).toBe(false);
          return true;
        },
      });
      expect(await run.finished).toEqual({ text: "Browser connected" });
      expect(chunks.join("")).toBe("Browser connected");
      expect(requests).toHaveLength(1);
      expect(requests[0]?.toolName).toBe("notch-browser status --json");
      expect(await readFile(marker, "utf8")).toBe("approved");
      const messages = (await readFile(log, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
      expect(messages.find((message) => message.id === "approval-1").result).toEqual({ decision: "accept" });
    });
  });

  test.each(["command", "file", "permissions"])("honors Deny for %s requests", async (mode) => {
    await withFixture(mode, async ({ adapter, workspace, marker }) => {
      let prompts = 0;
      const run = adapter.run({ type: "chat", text: "Check access", workspacePath: workspace }, {
        onActivity() {}, onChunk() {}, async onPermission() { prompts++; return false; },
      });
      expect((await run.finished).text).toBe("Permission denied");
      expect(prompts).toBe(1);
      expect(await Bun.file(marker).exists()).toBe(false);
    });
  });

  test.each(["file", "permissions"])("grants only the approved %s request for this turn", async (mode) => {
    await withFixture(mode, async ({ adapter, workspace, marker, log }) => {
      const run = adapter.run({ type: "chat", text: "Allow access", workspacePath: workspace }, {
        onActivity() {}, onChunk() {}, async onPermission() { return true; },
      });
      expect((await run.finished).text).toBe("Browser connected");
      expect(await Bun.file(marker).exists()).toBe(true);
      const messages = (await readFile(log, "utf8")).trim().split("\n").map((line) => JSON.parse(line));
      const response = messages.find((message) => message.id === "approval-1").result;
      expect(response).toEqual(mode === "file" ? { decision: "accept" } : {
        permissions: { network: { enabled: true } }, scope: "turn",
      });
    });
  });

  test("denies access when there is no approval callback", async () => {
    await withFixture("command", async ({ adapter, workspace, marker }) => {
      const run = adapter.run({ type: "chat", text: "Check access", workspacePath: workspace }, silentCallbacks());
      expect((await run.finished).text).toBe("Permission denied");
      expect(await Bun.file(marker).exists()).toBe(false);
    });
  });

  test("rejects approval requests from a different conversation", async () => {
    await withFixture("foreign", async ({ adapter, workspace, marker }) => {
      let prompts = 0;
      const run = adapter.run({ type: "chat", text: "Check access", workspacePath: workspace }, {
        ...silentCallbacks(), async onPermission() { prompts++; return true; },
      });
      expect((await run.finished).text).toBe("Permission denied");
      expect(prompts).toBe(0);
      expect(await Bun.file(marker).exists()).toBe(false);
    });
  });

  test("cancels while awaiting approval without executing the command", async () => {
    await withFixture("command", async ({ adapter, workspace, marker }) => {
      const waiting = Promise.withResolvers<void>();
      const decision = Promise.withResolvers<boolean>();
      const run = adapter.run({ type: "chat", text: "Check access", workspacePath: workspace }, {
        ...silentCallbacks(), onPermission() { waiting.resolve(); return decision.promise; },
      });
      await waiting.promise;
      run.cancel();
      expect(await run.finished).toEqual({ text: "" });
      decision.resolve(true);
      expect(await Bun.file(marker).exists()).toBe(false);
    });
  });

  test("does not duplicate streamed text when a completed item repeats it", async () => {
    await withFixture("stream", async ({ adapter, workspace }) => {
      const chunks: string[] = [];
      const run = adapter.run({ type: "chat", text: "Reply", workspacePath: workspace }, {
        onActivity() {}, onChunk(text) { chunks.push(text); },
      });
      expect((await run.finished).text).toBe("First message\n\nSecond message");
      expect(chunks.join("")).toBe("First message\n\nSecond message");
    });
  });

  test("fails clearly if the Codex process exits during a turn", async () => {
    await withFixture("crash", async ({ adapter, workspace }) => {
      const run = adapter.run({ type: "chat", text: "Reply", workspacePath: workspace }, silentCallbacks());
      await expect(run.finished).rejects.toThrow("Codex stopped before completing");
    });
  });
});

function silentCallbacks(): AgentStreamCallbacks {
  return { onActivity() {}, onChunk() {} };
}

