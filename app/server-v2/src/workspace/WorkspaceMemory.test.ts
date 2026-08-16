import { describe, expect, test } from "bun:test";

import {
  WORKSPACE_MEMORY_PATH,
  WORKSPACE_MEMORY_ROOT,
  WORKSPACE_USER_MEMORY_PATH,
  workspaceMemorySystemInstruction,
} from "./WorkspaceMemory";

describe("workspace memory protocol", () => {
  test("makes workspace memory available without forcing a read on every message", () => {
    const instruction = workspaceMemorySystemInstruction();

    expect(WORKSPACE_MEMORY_ROOT).toBe(".detach/memory");
    expect(WORKSPACE_MEMORY_PATH).toBe(".detach/memory/MEMORY.md");
    expect(WORKSPACE_USER_MEMORY_PATH).toBe(".detach/memory/USER.md");
    expect(instruction).toContain("relative to your current working directory");
    expect(instruction).toContain("optional capability, not a mandatory startup step");
    expect(instruction).toContain("Do not check or read memory for greetings");
    expect(instruction).toContain(`check whether \`${WORKSPACE_MEMORY_PATH}\` exists`);
    expect(instruction).not.toContain("At the start of a task");
    expect(instruction).toContain("Current");
    expect(instruction).toContain("episodic/YYYY-MM-DD.md");
    expect(instruction).toContain("routines/<routine-slug>/MEMORY.md");
    expect(instruction).toContain("Never record secrets");
  });
});
