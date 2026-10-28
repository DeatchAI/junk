/** Opt-in, sequential comparison against an already authorized Detach task and installed Cua daemon. */
import { CuaDriverPrototype } from "../src/desktop/prototype/CuaDriverPrototype";

const pid = Number(Bun.env.DETACH_COMPARE_PID);
const windowId = Number(Bun.env.DETACH_COMPARE_WINDOW_ID);
const runId = Bun.env.DETACH_DESKTOP_RUN_ID;
const token = Bun.env.DETACH_RUNTIME_TOKEN;
const url = Bun.env.DETACH_RUNTIME_URL ?? "http://127.0.0.1:3847";
if (process.argv.includes("--help") || !process.argv.includes("--live")) {
  console.log("Explicit opt-in: --live. Use only the disposable Detach Desktop Fixture. Required: DETACH_COMPARE_PID, DETACH_COMPARE_WINDOW_ID, DETACH_DESKTOP_RUN_ID, DETACH_RUNTIME_TOKEN, DETACH_CUA_DRIVER_PATH. Does not start a paid model call, install software or grant permissions.");
  process.exit(0);
}
if (!Number.isSafeInteger(pid) || pid < 1 || !Number.isSafeInteger(windowId) || windowId < 1 || !runId || !token) {
  throw new Error("Exact fixture pid/window, an active Detach task and runtime token are required");
}
const parsedURL = new URL(url);
if (parsedURL.hostname !== "127.0.0.1" || parsedURL.protocol !== "http:") throw new Error("Comparison only supports the authenticated local runtime");
const native = async (command: string, payload: Record<string, unknown>) => {
  const response = await fetch(`${url}/api/desktop/command`, { method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ command, payload, runId }), signal: AbortSignal.timeout(15_000) });
  const value = await response.json() as { ok?: boolean; result?: any; error?: string };
  if (!response.ok || !value.ok) throw new Error(value.error ?? "Native comparison failed");
  return value.result;
};
const cua = new CuaDriverPrototype();
const results: unknown[] = [];
for (const backend of ["native", "cua-driver"] as const) {
  let calls = 0;
  const execute = async (command: string, payload: Record<string, unknown>) => {
    calls++;
    return backend === "native" ? native(command, payload) : cua.execute(command, payload, runId) as Promise<any>;
  };
  const started = performance.now();
  try {
    const state = await execute("desktop.snapshot", { pid, windowId });
    const elements = state.elements as Array<Record<string, unknown>>;
    const field = elements.find((element) => element.identifier === "detach.fixture.field" || element.label === "Detach fixture text");
    if (!field || typeof field.ref !== "string") throw new Error("The disposable Detach Desktop Fixture field was not found; no mutation performed");
    const text = `Detach comparison ${backend}`;
    await execute("desktop.set_value", { pid, windowId, observationId: state.observationId, ref: field.ref, text });
    const after = await execute("desktop.snapshot", { pid, windowId });
    const passed = after.elements.some((item: Record<string, unknown>) => item.value === text);
    results.push({ backend, scenario: "replace-fixture-field-and-verify", passed, calls, durationMs: Math.round(performance.now() - started) });
  } catch (error) {
    results.push({ backend, scenario: "replace-fixture-field-and-verify", passed: false, calls,
      durationMs: Math.round(performance.now() - started), error: error instanceof Error ? error.message : String(error) });
  }
}
await cua.endRun(runId).catch(() => undefined);
console.log(JSON.stringify({ results, proof: "Deterministic fixture editing only; no model quality or general computer-use parity claim." }, null, 2));
