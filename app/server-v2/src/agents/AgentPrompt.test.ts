import { describe, expect, test } from "bun:test";
import type { ChatRequest } from "../protocol/messages";
import { agentAttachmentContext, buildAgentContent, buildAgentPrompt } from "./AgentPrompt";
import { buildCodexPrompt, codexAdditionalContext } from "./codex/CodexPrompt";
import { buildClaudeArgs } from "./ClaudeAdapter";

const plain: ChatRequest = { type: "chat", text: "Fix the button spacing.\nKeep the labels.",
  mcpServers: [{ id: "detach-capability-tools", name: "Detach", transport: "stdio", enabled: true,
    created_at: 0, updated_at: 0 }] };

describe("native message content", () => {
  test("plain and resumed turns contain exactly the user's text with tools connected", () => {
    for (const request of [plain, { ...plain, providerSessionId: "saved-thread" }]) {
      expect(buildAgentPrompt(request)).toBe(plain.text);
      expect(buildAgentContent(request)).toBe(plain.text);
      expect(buildCodexPrompt(request)).toBe(plain.text);
      expect(codexAdditionalContext(request)).toBeUndefined();
    }
  });

  test("Codex keeps explicitly chosen instructions separate from untrusted attachment context", () => {
    const request: ChatRequest = { ...plain, systemPrompt: "Use the selected review checklist.",
      attachmentContext: "Selected text: example", files: [{ path: "/tmp/reference.png", mimeType: "image/png" }],
      contextMessages: [{ role: "user", content: "Earlier question" }] };
    expect(buildCodexPrompt(request)).toBe(plain.text);
    expect(codexAdditionalContext(request)).toEqual({
      "detach.selected-instructions": { kind: "application", value: request.systemPrompt! },
      "detach.attachments": { kind: "untrusted", value: agentAttachmentContext(request) },
    });
    expect(agentAttachmentContext(request)).toContain("Earlier question");
    expect(agentAttachmentContext(request)).toContain("/tmp/reference.png");
  });

  test("Claude appends selected instructions without replacing its native system prompt", () => {
    const request = { ...plain, systemPrompt: "Check accessibility." };
    const args = buildClaudeArgs(buildAgentContent(request), request);
    expect(args[1]).toBe(plain.text);
    expect(args).toContain("--append-system-prompt");
    expect(args).not.toContain("--system-prompt");
    expect(args.at(-1)).toBe(request.systemPrompt);
  });

  test("fallback adapters retain only explicit context and instructions", () => {
    const request = { ...plain, systemPrompt: "Review only.", files: [{ path: "/tmp/example.txt" }] };
    expect(buildAgentPrompt(request)).toContain("Review only.");
    expect(buildAgentPrompt(request)).toContain("/tmp/example.txt");
    expect(buildAgentPrompt(request)).not.toContain("memory");
    expect(buildAgentPrompt(request)).not.toContain("capability directory");
  });
});
