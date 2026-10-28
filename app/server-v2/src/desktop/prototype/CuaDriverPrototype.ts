import { runCuaDriver, type DriverCall } from "./CuaDriverTransport";

const record = (value: unknown): Record<string, any> => value !== null && typeof value === "object" ? value as Record<string, any> : {};
interface Observation { id: string; pid: number; windowId: number; refs: Map<string, string> }

/** Comparison-only backend. No installation, account change, or runtime switch occurs implicitly. */
export class CuaDriverPrototype {
  private observations = new Map<string, Observation>();
  private ended = new Set<string>();
  private busy = new Set<number>();
  constructor(private readonly call: DriverCall = runCuaDriver) {}

  async execute(command: string, payload: Record<string, unknown>, runId: string) {
    if (!runId || this.ended.has(runId)) throw new Error("An active comparison task is required");
    const session = `detach-compare-${runId}`;
    if (command === "desktop.list_apps") return this.call("list_apps", { session });
    if (command === "desktop.list_windows") {
      return this.call("list_windows", { session, ...(payload.pid ? { pid: payload.pid } : {}),
        ...(payload.bundleId || payload.appName ? { app: payload.bundleId || payload.appName } : {}) });
    }
    if (["desktop.observe", "desktop.snapshot", "desktop.screenshot"].includes(command)) {
      if (!Number.isSafeInteger(payload.pid) || !Number.isSafeInteger(payload.windowId) || Number(payload.pid) < 1 || Number(payload.windowId) < 1) {
        throw new Error("The comparison backend requires exact pid and windowId");
      }
      const value = await this.call("get_window_state", { pid: payload.pid, window_id: payload.windowId,
        session, tree_format: "elements", include_screenshot: command !== "desktop.snapshot", max_elements: 500 });
      if (this.ended.has(runId)) throw new Error("Comparison task stopped during observation");
      const data = record(value.structuredContent);
      if (!Array.isArray(data.elements)) throw new Error("Unsupported Cua Driver response: structured elements are required");
      const observation: Observation = { id: crypto.randomUUID(), pid: Number(payload.pid), windowId: Number(payload.windowId), refs: new Map() };
      const elements = data.elements.map((item: unknown) => {
        const element = record(item);
        if (typeof element.element_token !== "string") return { ...element, ref: undefined };
        const ref = `${observation.id}:${element.element_token}`;
        observation.refs.set(ref, element.element_token);
        return { ...element, ref };
      });
      this.observations.set(runId, observation);
      return { backend: "cua-driver-prototype", observationId: observation.id, pid: observation.pid,
        windowId: observation.windowId, elements, content: value.content,
        hint: "Prototype comparison uses semantic refs. Native screenshot coordinates are never forwarded to another backend." };
    }
    const observation = this.observations.get(runId);
    if (!observation || payload.observationId !== observation.id) throw new Error("Stale or foreign comparison observation");
    if (payload.allowForeground === true) throw new Error("Comparison prototype does not permit foreground escalation");
    if (payload.pid !== undefined && payload.pid !== observation.pid || payload.windowId !== undefined && payload.windowId !== observation.windowId) {
      throw new Error("Comparison target mismatch");
    }
    const token = observation.refs.get(String(payload.ref));
    if (!token) throw new Error("A fresh semantic comparison ref is required; coordinates are unsupported");
    const tool = command === "desktop.click" ? "click" : command === "desktop.type" && payload.replace !== true ? "type_text"
      : ["desktop.type", "desktop.set_value"].includes(command) ? "set_value" : undefined;
    if (!tool) throw new Error(`The comparison prototype does not support ${command}`);
    if (this.busy.has(observation.pid)) throw new Error("Another comparison task is controlling this app");
    if (tool !== "click" && typeof payload.text !== "string") throw new Error("text is required");
    this.busy.add(observation.pid);
    this.observations.delete(runId); // one observation cannot authorize a repeated action
    try {
      const result = await this.call(tool, { session, pid: observation.pid, window_id: observation.windowId,
        element_token: token, ...(tool === "click" ? {} : tool === "set_value" ? { value: payload.text } : { text: payload.text }) });
      return { backend: "cua-driver-prototype", driverResult: result,
        inputDelivered: !result.isError, effectVerified: false,
        hint: "Observe the window and verify the requested result; a successful driver call is not task success." };
    } finally { this.busy.delete(observation.pid); }
  }

  async endRun(runId: string) {
    if (this.ended.has(runId)) return;
    this.ended.add(runId);
    this.observations.delete(runId);
    await this.call("end_session", { session: `detach-compare-${runId}` });
  }
}
