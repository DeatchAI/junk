import { expect, test } from "bun:test";
import { validateDesktopCommand } from "./DesktopValidation";

test("desktop schema rejects ambiguous numeric coercion, invalid modifiers and arbitrary arguments", () => {
  for (const payload of [{ pid: true }, { pid: 1.2 }, { pid: -1 }, { pid: Infinity }, { windowId: NaN }, { unknown: 1 }]) {
    expect(() => validateDesktopCommand("desktop.observe", payload)).toThrow();
  }
  expect(() => validateDesktopCommand("desktop.key", { observationId: "a", key: "s", modifiers: ["bogus"] })).toThrow();
  expect(() => validateDesktopCommand("desktop.key", { key: "s" })).toThrow("observationId");
  expect(() => validateDesktopCommand("desktop.observe", { pid: 42, windowId: 5, ocr: true })).not.toThrow();
});
