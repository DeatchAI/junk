import { expect, test } from "bun:test";
import { assertACPCompletion } from "./ACPCompletion";

test("ACP cancellation, refusal and limits are not mistaken for success after progress text", () => {
  for (const stopReason of ["cancelled", "refusal", "max_tokens", "max_turn_requests", "unexpected"]) {
    expect(() => assertACPCompletion({ stopReason }, true, true, false)).toThrow("saved conversation");
  }
});

test("an agent ending after a tool without a final answer remains visibly incomplete", () => {
  expect(() => assertACPCompletion({ stopReason: "end_turn" }, true, true, false)).toThrow("no final response");
  expect(() => assertACPCompletion({ stopReason: "end_turn" }, true, true, true)).not.toThrow();
  expect(() => assertACPCompletion({ stopReason: "end_turn" }, true, false, false)).not.toThrow();
});
