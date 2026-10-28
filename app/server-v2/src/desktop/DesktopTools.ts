type Property = Record<string, unknown>;
const integer = (minimum: number, maximum?: number): Property => ({ type: "integer", minimum, ...(maximum === undefined ? {} : { maximum }) });
const text: Property = { type: "string" };
const flag: Property = { type: "boolean" };
const target = { pid: integer(1), bundleId: text, appName: text, windowId: integer(1) };
const observation = { ...target, observationId: { ...text, description: "ID from this task's latest window observation." } };
const input = { ...observation, ref: text, screenshotId: text,
  allowForeground: { ...flag, description: "Explicitly permit foreground input. Default false; never enabled as an automatic fallback." },
  waitMs: integer(0, 3000) };
const point = { x: { type: "number", minimum: 0 }, y: { type: "number", minimum: 0 } };
const capture = { ...target, maxDepth: integer(1, 32), maxElements: integer(1, 1500),
  maxWidth: integer(320, 3840), diff: flag, includeScreenshot: flag,
  ocr: { ...flag, description: "Optional local Apple Vision text recognition. No external model or upload." } };

function tool(name: string, description: string, properties: Record<string, Property>, required: string[] = []) {
  return { name: `detach_macos_${name}`, description,
    inputSchema: { type: "object", properties, required, additionalProperties: false } };
}
export const MACOS_TOOLS = [
  tool("status", "Check Detach's macOS connection and OS permissions. No input or model call.", {}),
  tool("list_apps", "List running apps and their process IDs.", {}),
  tool("list_windows", "List an app's windows. Select an exact windowId before observing an app with multiple windows.", target),
  tool("open_app", "Open an installed app in the background; does not activate it. List windows afterward.", { bundleId: text, appName: text }),
  tool("activate_app", "Explicitly foreground the window from a fresh observation. Requires allowForeground:true.", input, ["observationId", "allowForeground"]),
  tool("observe", "Observe one exact window: accessibility tree, image, observationId, screenshotId and pixel-to-screen map. Optional local OCR. No activation. Missing optional screen permission still permits tree inspection.", capture),
  tool("snapshot", "Inspect an exact window's accessibility tree without a screenshot. Refs are task-owned and expire on the next observation. diff:true returns changed nodes only; unchanged refs expire too.", capture),
  tool("screenshot", "Capture the selected window, with its accessibility state and coordinate map. Requires Screen Recording. Coordinates must use this screenshotId and observationId.", capture),
  tool("click", "Press a fresh element ref through accessibility, otherwise use targeted process input. Pixel clicks need both screenshotId and observationId. Returns fresh UI state and verification evidence.", { ...input, ...point, button: { type: "string", enum: ["left", "right"] }, clickCount: integer(1, 3) }),
  tool("type", "Insert text at a fresh field ref's current caret/selection, or replace:true for the entire value. Refuses secure fields and ambiguous insertion points. Reads the value back to verify.", { ...input, text, replace: flag }, ["ref", "text"]),
  tool("set_value", "Set a non-secure editable control's whole value and verify readback.", { ...input, text }, ["ref", "text"]),
  tool("select_text", "Select one unique text span in a fresh editable ref, or position its caret before/after that span.", { ...input, text, selectionType: { type: "string", enum: ["text", "cursor_before", "cursor_after"] } }, ["ref", "text"]),
  tool("perform_action", "Invoke an accessibility action actually listed on a fresh element (for example AXShowMenu). Never invent action names.", { ...input, action: text }, ["ref", "action"]),
  tool("key", "Send a shortcut to the observed app/window. Uses targeted background delivery; refuses ambiguous focus or secure fields. Never silently falls back to global input.", { ...observation, allowForeground: input.allowForeground, waitMs: input.waitMs, key: text, modifiers: { type: "array", items: { type: "string", enum: ["command", "option", "control", "shift", "fn"] } }, repeat: integer(1, 20) }, ["observationId", "key"]),
  tool("scroll", "Scroll over an element ref or observed image coordinates in the target window; positive deltaY scrolls up. Returns fresh state.", { ...input, ...point, deltaX: { type: "number" }, deltaY: { type: "number" } }),
  tool("drag", "Drag from a ref or screenshot pixel to endX,endY in the same screenshot. Requires screenshotId and a current observationId. Cancellation releases the mouse.", { ...input, ...point, endX: point.x, endY: point.y }, ["observationId", "screenshotId", "endX", "endY"]),
  tool("wait", "Wait up to timeoutMs for visible text in an exact window, returning matched:false on timeout. Does not act or change focus.", { ...target, text, timeoutMs: integer(0, 10000) }, ["text"]),
];
export const MACOS_TOOL_NAMES = MACOS_TOOLS.map((item) => item.name);
export const MACOS_TOOL_COMMANDS = Object.fromEntries(MACOS_TOOLS.map((item) => [item.name, `desktop.${item.name.slice("detach_macos_".length)}`]));
