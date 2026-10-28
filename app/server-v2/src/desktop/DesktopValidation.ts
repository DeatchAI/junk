import { MACOS_TOOLS, MACOS_TOOL_COMMANDS } from "./DesktopTools";

type Schema = { type?: string; enum?: unknown[]; minimum?: number; maximum?: number; items?: Schema };

export function validateDesktopCommand(command: string, payload: Record<string, unknown>) {
  const tool = MACOS_TOOLS.find((item) => MACOS_TOOL_COMMANDS[item.name] === command);
  if (!tool) throw new Error(`Unknown macOS command: ${command}`);
  const properties = tool.inputSchema.properties as Record<string, Schema>;
  for (const key of tool.inputSchema.required) {
    if (payload[key] === undefined) throw new Error(`${key} is required for ${command}`);
  }
  for (const [key, value] of Object.entries(payload)) {
    if (!properties[key]) throw new Error(`Unknown macOS argument: ${key}`);
    validate(value, properties[key]!, key);
  }
}

function validate(value: unknown, schema: Schema, path: string) {
  if (schema.type === "integer" || schema.type === "number") {
    if (typeof value !== "number" || !Number.isFinite(value) || schema.type === "integer" && !Number.isSafeInteger(value) ||
      schema.minimum !== undefined && value < schema.minimum || schema.maximum !== undefined && value > schema.maximum) {
      throw new Error(`Invalid numeric macOS argument: ${path}`);
    }
  } else if (schema.type === "array") {
    if (!Array.isArray(value) || value.length > 16) throw new Error(`Invalid macOS array: ${path}`);
    for (const entry of value) validate(entry, schema.items ?? {}, path);
  } else if (schema.type && typeof value !== schema.type) {
    throw new Error(`Invalid macOS argument type: ${path}`);
  }
  if (schema.enum && !schema.enum.includes(value)) throw new Error(`Invalid macOS argument: ${path}`);
  if (typeof value === "string" && value.length > 100_000) throw new Error(`macOS argument is too large: ${path}`);
}
