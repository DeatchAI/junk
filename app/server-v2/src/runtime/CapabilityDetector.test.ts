import { describe, expect, test } from "bun:test";

import { parseFxModels, parseFxStatus, parseOpenCodeModels } from "./CapabilityDetector";

describe("fx model discovery", () => {
  test("parses and humanizes the fx JSON model catalog", () => {
    expect(parseFxModels(JSON.stringify({
      kind: "models",
      ids: ["zai/glm-5.2-fast", "openai/gpt-5.4", "zai/glm-5.2-fast"],
    }))).toEqual([
      { id: "zai/glm-5.2-fast", displayName: "zai · GLM 5.2 Fast" },
      { id: "openai/gpt-5.4", displayName: "openai · GPT 5.4" },
    ]);
  });

  test("parses fx authentication guidance and its selected model", () => {
    expect(parseFxStatus(JSON.stringify({
      kind: "status",
      model: "zai/glm-5.2-fast",
      auth: "missing",
      auth_help: "Run fx login",
    }))).toEqual({
      model: "zai/glm-5.2-fast",
      auth: "missing",
      authHelp: "Run fx login",
    });
  });
});

describe("OpenCode model discovery", () => {
  test("keeps active tool-capable models from OpenCode's verbose catalog", () => {
    const models = parseOpenCodeModels(`
openai/gpt-5.4
{
  "id": "gpt-5.4",
  "providerID": "openai",
  "name": "GPT-5.4",
  "status": "active",
  "capabilities": { "toolcall": true }
}
example/chat-only
{
  "id": "chat-only",
  "providerID": "example",
  "name": "Chat only",
  "status": "active",
  "capabilities": { "toolcall": false }
}
example/retired
{
  "id": "retired",
  "providerID": "example",
  "name": "Retired",
  "status": "deprecated",
  "capabilities": { "toolcall": true }
}`);

    expect(models).toEqual([{
      id: "openai/gpt-5.4",
      displayName: "openai · GPT-5.4",
    }]);
  });

  test("parses braces within model metadata without splitting the model object", () => {
    const models = parseOpenCodeModels(`
provider/example
{
  "id": "example",
  "providerID": "provider",
  "name": "Example {Tools}",
  "capabilities": { "toolcall": true }
}`);

    expect(models[0]?.id).toBe("provider/example");
  });

  test("keeps model-specific reasoning levels from the verbose catalog", () => {
    const models = parseOpenCodeModels(`
openai/gpt-5.6
{
  "id": "gpt-5.6",
  "providerID": "openai",
  "name": "GPT-5.6",
  "status": "active",
  "capabilities": { "toolcall": true },
  "reasoning_options": [{ "type": "effort", "values": ["low", "medium", "high", "xhigh"] }]
}`);

    expect(models).toEqual([{
      id: "openai/gpt-5.6",
      displayName: "openai · GPT-5.6",
      reasoningEfforts: ["low", "medium", "high", "xhigh"],
      reasoningLabel: "Effort",
    }]);
  });
});
