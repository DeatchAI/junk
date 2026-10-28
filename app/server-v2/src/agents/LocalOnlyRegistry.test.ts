import { describe, expect, test } from "bun:test";
import { AgentRegistry } from "./AgentRegistry";
import { standaloneOpenCodeEnvironment } from "./OpenCodeAdapter";

describe("local-agent launch configuration", () => {
  test("offers only the user's own agent harnesses and rejects retired hosted selections", () => {
    const registry = new AgentRegistry();
    for (const agent of ["codex", "claude", "grok", "fx", "opencode", "pi", "amp", "omp"]) {
      expect(registry.has(agent)).toBe(true);
    }
    expect(registry.has("hosted")).toBe(false);
    expect(() => registry.get("hosted" as never)).toThrow("Unknown agent");
    registry.setCurrentAgent("hosted" as never);
    expect(registry.getCurrentAgent()).toBe("codex");
  });

  test("OpenCode inherits the user's own credentials and provider configuration", () => {
    const environment = standaloneOpenCodeEnvironment();
    expect(environment).toEqual({ OPENCODE_DISABLE_AUTOUPDATE: "true", NO_COLOR: "1" });
    expect(environment).not.toHaveProperty("OPENCODE_CONFIG_CONTENT");
    expect(environment).not.toHaveProperty("DETACH_HOSTED_MODEL_TOKEN");
    expect(environment).not.toHaveProperty("XDG_CONFIG_HOME");
  });
});
