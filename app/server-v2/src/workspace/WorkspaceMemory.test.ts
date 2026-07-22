import { describe, expect, test } from "bun:test";

import {
  WORKSPACE_MEMORY_PATH,
  WORKSPACE_MEMORY_ROOT,
  WORKSPACE_USER_MEMORY_PATH,
  workspaceMemorySystemInstruction,
} from "./WorkspaceMemory";

describe("workspace memory protocol", () => {
  test("directs every agent to discover a workspace-local taxonomy without injecting its contents", () => {
    const instruction = workspaceMemorySystemInstruction();

    expect(WORKSPACE_MEMORY_ROOT).toBe(".detach/memory");
    expect(WORKSPACE_MEMORY_PATH).toBe(".detach/memory/MEMORY.md");
    expect(WORKSPACE_USER_MEMORY_PATH).toBe(".detach/memory/USER.md");
    expect(instruction).toContain("relative to your current working directory");
    expect(instruction).toContain(`check whether \`${WORKSPACE_MEMORY_PATH}\` exists`);
    expect(instruction).toContain("Current");
    expect(instruction).toContain("episodic/YYYY-MM-DD.md");
    expect(instruction).toContain("routines/<routine-slug>/MEMORY.md");
    expect(instruction).toContain("Never record secrets");
  });
});
