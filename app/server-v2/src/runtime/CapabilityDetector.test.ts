import { describe, expect, test } from "bun:test";

import { parseOpenCodeModels } from "./CapabilityDetector";

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
