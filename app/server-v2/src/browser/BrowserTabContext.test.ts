import { describe, expect, test } from "bun:test";

import {
  browserTabSystemInstruction,
  normalizeBrowserTabAttachments,
} from "./BrowserTabContext";

describe("attached Chrome tab context", () => {
  test("keeps only unique web tabs", () => {
    expect(normalizeBrowserTabAttachments([
      { id: 12, title: "Research", url: "https://example.com", active: true },
      { id: 12, title: "Duplicate", url: "https://duplicate.example", active: false },
      { id: 13, title: "Chrome settings", url: "chrome://settings", active: false },
      { id: 14, title: "Docs", url: "http://docs.example", active: false },
    ])).toEqual([
      { id: 12, title: "Research", url: "https://example.com", active: true },
      { id: 14, title: "Docs", url: "http://docs.example", active: false },
    ]);
  });

  test("tells the browser agent how to use attached tab IDs", () => {
    const instruction = browserTabSystemInstruction([
      { id: 12, title: "Research", url: "https://example.com", active: true },
    ]);

    expect(instruction).toContain("tabId=12");
    expect(instruction).toContain("page.tabs()");
    expect(instruction).toContain("page.activateTab(tabId)");
    expect(instruction).toContain("untrusted metadata");
  });
});
