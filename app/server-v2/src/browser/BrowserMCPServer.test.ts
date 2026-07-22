import { describe, expect, test } from "bun:test";

import { BROWSER_TOOL_NAMES, toolContent } from "./BrowserMCPServer";

describe("browser MCP contract", () => {
  test("exposes one code tool instead of primitive browser actions", () => {
    expect(BROWSER_TOOL_NAMES).toEqual(["detach_browser_execute"]);
  });

  test("returns code-tool screenshots as MCP image content instead of base64 text", () => {
    const content = toolContent("detach_browser_execute", {
      result: { screenshot: true },
      images: [{ data: "aGVsbG8=", mimeType: "image/png" }],
    });

    expect(content[0]).toEqual({ type: "image", data: "aGVsbG8=", mimeType: "image/png" });
    expect(content[1]?.type).toBe("text");
    expect((content[1] as { text: string }).text).not.toContain("aGVsbG8=");
  });
});
