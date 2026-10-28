import { expect, test } from "bun:test";
import { CuaDriverPrototype } from "./CuaDriverPrototype";

test("Cua comparison binds refs to its own task/window and consumes observations before input", async () => {
  const calls: Array<{ tool: string; args: Record<string, unknown> }> = [];
  const driver = new CuaDriverPrototype(async (tool, args) => {
    calls.push({ tool, args });
    return { structuredContent: { elements: [{ element_token: "s1:0", label: "Field" }] }, content: [] };
  });
  const a = await driver.execute("desktop.observe", { pid: 41, windowId: 7 }, "a") as any;
  await expect(driver.execute("desktop.click", { observationId: a.observationId, ref: a.elements[0].ref }, "b")).rejects.toThrow("foreign");
  await expect(driver.execute("desktop.click", { observationId: a.observationId, ref: a.elements[0].ref, allowForeground: true }, "a")).rejects.toThrow("foreground");
  await driver.execute("desktop.set_value", { observationId: a.observationId, ref: a.elements[0].ref, text: "Detach" }, "a");
  expect(calls.at(-1)).toEqual({ tool: "set_value", args: { session: "detach-compare-a", pid: 41, window_id: 7, element_token: "s1:0", value: "Detach" } });
  await expect(driver.execute("desktop.click", { observationId: a.observationId, ref: a.elements[0].ref }, "a")).rejects.toThrow("foreign");
  await driver.endRun("a");
  await expect(driver.execute("desktop.observe", { pid: 41, windowId: 7 }, "a")).rejects.toThrow("active");
  expect(calls.at(-1)?.tool).toBe("end_session");
});

test("Cua comparison rejects unstructured snapshots instead of inventing tokens", async () => {
  const driver = new CuaDriverPrototype(async () => ({ content: [] }));
  await expect(driver.execute("desktop.observe", { pid: 1, windowId: 2 }, "a")).rejects.toThrow("structured elements");
});
