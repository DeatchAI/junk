import { describe, expect, test } from "bun:test";

import { compactBrowserSnapshot } from "./BrowserSnapshot";

describe("compact browser snapshots", () => {
  test("prunes verbose engine payloads into a semantic tree and compact diff", () => {
    const snapshot = compactBrowserSnapshot({
      url: "https://example.com",
      title: "Example",
      text: "A very long body that should stay private by default",
      meta: { headings: [{ text: "Checkout" }] },
      elements: [
        { ref: "e1", role: "button", name: "Pay", depth: 2 },
        { ref: "e2", role: "button", name: "Pay", depth: 4 },
        { ref: "e3", role: "textbox", name: "Email", value: "a@example.com", required: true },
      ],
      delta: { changed: [{ ref: "e3", role: "textbox", name: "Email" }], removedRefs: ["e0"] },
    });

    expect(snapshot).not.toHaveProperty("text");
    const tree = String(snapshot.tree || "");
    expect(tree).toContain("heading \"Checkout\"");
    expect(tree.match(/button \"Pay\"/g)).toHaveLength(1);
    expect(tree).toContain("textbox \"Email\" [ref=e3 value=\"a@example.com\" required]");
    expect(snapshot.changes).toEqual({ changed: ['- textbox "Email" [ref=e3]'], removedRefs: ["e0"] });
  });

  test("keeps identical controls distinct when they belong to different frames", () => {
    const snapshot = compactBrowserSnapshot({
      frames: [
        { frameId: 0, parentFrameId: -1, url: "https://example.com", main: true },
        { frameId: 7, parentFrameId: 0, url: "https://pay.example.com" },
      ],
      elements: [
        { ref: "main-submit", frameId: 0, role: "button", name: "Submit" },
        { ref: "frame-submit", frameId: 7, role: "button", name: "Submit" },
      ],
      tables: [{ frameId: 7, rows: [["Plan", "Pro"]] }],
    });

    expect(String(snapshot.tree).match(/button "Submit"/g)).toHaveLength(2);
    expect(snapshot.tree).toContain("[ref=frame-submit frame=7]");
    expect(snapshot.frames).toHaveLength(2);
    expect(snapshot.tables).toEqual([{ frameId: 7, rows: [["Plan", "Pro"]] }]);
  });
});
