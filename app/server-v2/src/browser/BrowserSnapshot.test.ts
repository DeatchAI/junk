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
});
