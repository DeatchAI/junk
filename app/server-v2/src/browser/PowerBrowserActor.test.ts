import { describe, expect, test } from "bun:test";

import { parseSemanticElements } from "./PowerBrowserActor";

describe("Power browser semantic snapshots", () => {
  test("uses stable backend node ids for interactive refs", () => {
    const strings = ["HTML", "BODY", "BUTTON", "aria-label", "Save", "button", "name", "saveAction"];
    const snapshot = {
      strings,
      documents: [{
        frameId: "frame-main",
        nodes: {
          backendNodeId: [1, 2, 42],
          nodeName: [0, 1, 2],
          parentIndex: [-1, 0, 1],
          attributes: [[], [], [3, 4, 6, 7]],
          isClickable: { index: [2] },
        },
        layout: {
          nodeIndex: [0, 1, 2],
          bounds: [[0, 0, 1280, 800], [0, 0, 1280, 800], [100, 120, 80, 32]],
        },
      }],
    };
    const axTree = {
      nodes: [{ backendDOMNodeId: 42, role: { value: "button" }, name: { value: "Save" } }],
    };

    const first = parseSemanticElements(snapshot, axTree, "target-abcdef", 20);
    const second = parseSemanticElements(snapshot, axTree, "target-abcdef", 20);

    expect(first).toHaveLength(1);
    expect(first[0]).toMatchObject({
      ref: "cdp-abcdef-42",
      backendNodeId: 42,
      role: "button",
      name: "Save",
      htmlName: "saveAction",
      rect: { x: 100, y: 120, width: 80, height: 32 },
    });
    expect(second[0]?.ref).toBe(first[0]?.ref);
  });
});
