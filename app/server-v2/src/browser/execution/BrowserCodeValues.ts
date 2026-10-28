import * as ts from "typescript";

export interface BrowserPrimitiveHost {
  primitive(command: string, payload: Record<string, unknown>, record?: boolean): Promise<unknown>;
}

export type BrowserPrimitiveRunner = (command: string, payload: Record<string, unknown>) => Promise<unknown>;
export type BrowserPrimitiveObserver = (update: BrowserPrimitiveUpdate) => void;

export interface BrowserPrimitiveUpdate {
  id: string;
  command: string;
  payload: Record<string, unknown>;
  phase: "started" | "completed" | "failed";
  error?: string;
}

export interface BrowserCodeExecution {
  result: unknown;
  operations: BrowserCodeOperation[];
  events: unknown[];
  images: Array<{ data: string; mimeType: string }>;
}

export interface BrowserCodeOperation {
  operation: string;
  durationMs: number;
  ok: boolean;
  error?: string;
}

export interface LocatorSpec {
  kind: "selector" | "text" | "role" | "label" | "placeholder" | "ref";
  value: string;
  name?: string;
  exact?: boolean;
  many?: boolean;
  index?: number;
  frameSelector?: string;
  frameId?: number;
  documentId?: string;
}

export interface SafeFunction {
  kind: "safe_function";
  node: ts.ArrowFunction | ts.FunctionExpression;
  environment: Environment;
}

export interface ReturnSignal {
  kind: "return";
  value: unknown;
}

export class Environment {
  private readonly values = new Map<string, unknown>();

  constructor(private readonly parent?: Environment) {}

  declare(name: string, value: unknown) {
    this.values.set(name, value);
  }

  get(name: string): unknown {
    if (this.values.has(name)) return this.values.get(name);
    if (this.parent) return this.parent.get(name);
    throw new Error(`Browser code uses an unknown identifier: ${name}`);
  }

  assign(name: string, value: unknown): unknown {
    if (this.values.has(name)) {
      this.values.set(name, value);
      return value;
    }
    if (this.parent) return this.parent.assign(name, value);
    throw new Error(`Browser code cannot assign undeclared identifier: ${name}`);
  }
}

export class PageHandle {
  readonly keyboard = new KeyboardHandle(this);
  readonly media = new MediaHandle(this);

  constructor(readonly executor: BrowserPrimitiveHost) {}
}

export class MediaHandle {
  constructor(readonly page: PageHandle) {}
}

export class FrameLocatorHandle {
  frameId?: number;
  documentId?: string;

  constructor(readonly page: PageHandle, readonly selector: string) {}
}

export class KeyboardHandle {
  constructor(readonly page: PageHandle) {}
}

export class LocatorHandle {
  resolvedTarget?: Record<string, unknown>;

  constructor(readonly page: PageHandle, readonly spec: LocatorSpec) {}
}

export class DocumentHandle {
  constructor(readonly page: PageHandle) {}
}

export class WindowHandle {
  constructor(readonly page: PageHandle) {}
}

export class LocationHandle {
  constructor(readonly page: PageHandle) {}
}

export class DOMElementHandle {
  constructor(readonly data: Record<string, unknown>) {}
}

export class ConsoleHandle {}

export class BuiltinHandle {
  constructor(readonly name: "JSON" | "Math" | "String" | "Number" | "Boolean" | "Object" | "Array") {}
}

export const BLOCKED_PROPERTIES = new Set(["__proto__", "prototype", "constructor", "caller", "callee"]);
export const PAGE_METHODS = new Set([
  "status", "goto", "open", "snapshot", "text", "tabs", "activeTab", "activateTab", "closeTab",
  "back", "forward", "reload", "waitFor", "waitForURL", "waitForEvent", "events", "screenshot", "acceptDialog", "dismissDialog",
  "frames", "frameLocator", "table", "artifact", "artifacts",
  "getByRole", "getByText", "getByLabel", "getByPlaceholder", "locator", "ref", "url", "title", "evaluate",
]);
export const MAX_CODE_LENGTH = 20_000;
export const MAX_LOOP_ITERATIONS = 1_000;

export function sanitizeResult(value: unknown, depth = 0): unknown {
  if (depth > 12) return "[max depth]";
  if (value instanceof LocatorHandle) return { locator: value.spec };
  if (value instanceof PageHandle) return { page: true };
  if (value instanceof KeyboardHandle) return { keyboard: true };
  if (value instanceof MediaHandle) return { media: true };
  if (value instanceof FrameLocatorHandle) return { frameLocator: value.selector };
  if (value instanceof DOMElementHandle) return sanitizeResult(value.data, depth + 1);
  if (
    value instanceof DocumentHandle
    || value instanceof WindowHandle
    || value instanceof LocationHandle
    || value instanceof BuiltinHandle
    || value instanceof ConsoleHandle
    || isSafeFunction(value)
  ) return undefined;
  if (Array.isArray(value)) return value.slice(0, 1_000).map((item) => sanitizeResult(item, depth + 1));
  if (isPlainRecord(value)) {
    return Object.fromEntries(Object.entries(value).filter(([key]) => key !== "data" && key !== "dataUrl")
      .map(([key, item]) => [key, sanitizeResult(item, depth + 1)]));
  }
  return value;
}

export function propertyName(name: ts.PropertyName) {
  if (ts.isIdentifier(name) || ts.isStringLiteralLike(name) || ts.isNumericLiteral(name)) return name.text;
  throw new Error("Browser code object keys must be identifiers, strings, or numbers");
}

export function isSafeFunction(value: unknown): value is SafeFunction {
  return Boolean(value && typeof value === "object" && (value as SafeFunction).kind === "safe_function");
}

export function isReturnSignal(value: unknown): value is ReturnSignal {
  return Boolean(value && typeof value === "object" && (value as ReturnSignal).kind === "return");
}

export function isPlainRecord(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

export function asRecord(value: unknown): Record<string, any> {
  return isPlainRecord(value) ? value as Record<string, any> : {};
}

export function normalize(value: unknown) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim().toLocaleLowerCase() : "";
}

export function requireString(value: unknown, name: string) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`Browser code needs ${name}`);
  return value;
}

export function requireStringOrNumber(value: unknown, name: string) {
  if (typeof value === "string" && value.trim()) return value;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  throw new Error(`Browser code needs ${name}`);
}

export function stringValue(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

export function urlMatches(actual: string, expected: string) {
  if (!expected.includes("*")) return actual === expected || actual.includes(expected);
  const source = expected.split("*").map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*");
  return new RegExp(`^${source}$`).test(actual);
}

export function numberOr(value: unknown, fallback: number) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

export function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  return Math.min(max, Math.max(min, numberOr(value, fallback)));
}

export function waitTimeout(value: Record<string, unknown>) {
  return clampNumber(value.timeoutMs ?? value.timeout, 100, 60_000, 10_000);
}

export function cssEscape(value: string) {
  return value.replace(/[^a-zA-Z0-9_-]/g, (character) => `\\${character.codePointAt(0)!.toString(16)} `);
}

export function cssAttributeEscape(value: string) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}
