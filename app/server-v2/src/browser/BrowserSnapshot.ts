export interface CompactSnapshotOptions {
  includeText?: boolean;
  includeTables?: boolean;
  maxLines?: number;
  maxTextLength?: number;
}

/**
 * Converts the engine-specific DOM/AX payload into the small representation
 * exposed to the model-facing browser code tool. The full structured payload
 * remains private so locators can still resolve reliable element refs.
 */
export function compactBrowserSnapshot(value: unknown, options: CompactSnapshotOptions = {}) {
  const snapshot = asRecord(value);
  const elements = Array.isArray(snapshot.elements)
    ? snapshot.elements.map(asRecord).filter((element) => Object.keys(element).length > 0)
    : [];
  const maxLines = clampNumber(options.maxLines, 20, 240, 140);
  const lines: string[] = [];
  const seen = new Set<string>();

  const headings = Array.isArray(asRecord(snapshot.meta).headings)
    ? asRecord(snapshot.meta).headings as Array<Record<string, unknown>>
    : [];
  for (const heading of headings) {
    const record = asRecord(heading);
    const text = clean(record.text);
    if (!text) continue;
    appendUnique(lines, seen, `- heading ${quoted(text)}`, maxLines);
  }

  for (const element of elements) {
    if (lines.length >= maxLines) break;
    const line = semanticLine(element);
    if (line) appendUnique(lines, seen, line, maxLines);
  }

  const tables = options.includeTables === false
    ? undefined
    : compactTables(snapshot.tables, 8, 30, 12);
  const text = options.includeText
    ? truncate(clean(snapshot.text), clampNumber(options.maxTextLength, 500, 20_000, 6_000))
    : undefined;

  return removeUndefined({
    url: stringValue(snapshot.url),
    title: stringValue(snapshot.title),
    readyState: stringValue(snapshot.readyState),
    snapshotVersion: numberValue(snapshot.snapshotVersion),
    frames: compactFrames(snapshot.frames),
    tree: lines.join("\n"),
    text,
    tables,
    changes: compactChanges(snapshot.delta),
    stats: {
      nodes: elements.length,
      shown: lines.length,
      truncated: elements.length > lines.length,
    },
  });
}

function semanticLine(element: Record<string, unknown>) {
  const role = clean(element.role || element.tag || "element").toLowerCase() || "element";
  const name = clean(element.name || element.text || element.placeholder || element.href || "");
  const value = clean(element.value || "");
  const ref = clean(element.ref || "");
  const depth = Math.min(4, Math.max(0, numberValue(element.depth) ?? 0));
  const state: string[] = [];

  if (ref) state.push(`ref=${ref}`);
  if (Number.isInteger(element.frameId) && Number(element.frameId) !== 0) state.push(`frame=${element.frameId}`);
  if (value && value !== name && value !== "[password]") state.push(`value=${quoted(value)}`);
  if (value === "[password]") state.push("value=[password]");
  if (element.checked === true) state.push("checked");
  if (element.selected === true) state.push("selected");
  if (element.expanded === true) state.push("expanded");
  if (element.disabled === true) state.push("disabled");
  if (element.required === true) state.push("required");
  const type = clean(element.type || "");
  const autocomplete = clean(element.autocomplete || "");
  if (type && type !== "text") state.push(`type=${type}`);
  if (autocomplete) state.push(`autocomplete=${autocomplete}`);

  if (!name && !ref && state.length === 0) return undefined;
  const indent = "  ".repeat(depth);
  return `${indent}- ${role}${name ? ` ${quoted(name)}` : ""}${state.length ? ` [${state.join(" ")}]` : ""}`;
}

function compactChanges(value: unknown) {
  const delta = asRecord(value);
  const changed = Array.isArray(delta.changed)
    ? delta.changed.map(asRecord).map(semanticLine).filter((line): line is string => Boolean(line)).slice(0, 40)
    : [];
  const removedRefs = Array.isArray(delta.removedRefs)
    ? delta.removedRefs.filter((ref): ref is string => typeof ref === "string").slice(0, 40)
    : [];
  if (changed.length === 0 && removedRefs.length === 0) return undefined;
  return removeUndefined({ changed: changed.length ? changed : undefined, removedRefs: removedRefs.length ? removedRefs : undefined });
}

function compactTables(value: unknown, maxTables: number, maxRows: number, maxColumns: number) {
  if (!Array.isArray(value)) return undefined;
  const tables = value.slice(0, maxTables).map((table) => {
    const record = asRecord(table);
    const rows = Array.isArray(record.rows)
      ? record.rows.slice(0, maxRows).map((row) => Array.isArray(row)
        ? row.slice(0, maxColumns).map((cell) => truncate(clean(cell), 240))
        : [])
      : [];
    return removeUndefined({
      caption: clean(record.caption) || undefined,
      frameId: Number.isInteger(record.frameId) ? record.frameId : undefined,
      rows,
    });
  }).filter((table) => Array.isArray(table.rows) && table.rows.length > 0);
  return tables.length ? tables : undefined;
}

function compactFrames(value: unknown) {
  if (!Array.isArray(value)) return undefined;
  const frames = value.slice(0, 50).map((frame) => {
    const record = asRecord(frame);
    return removeUndefined({
      frameId: Number.isInteger(record.frameId) ? record.frameId : undefined,
      parentFrameId: Number.isInteger(record.parentFrameId) ? record.parentFrameId : undefined,
      url: truncate(clean(record.url), 500) || undefined,
      main: record.main === true || undefined,
    });
  }).filter((frame) => frame.frameId !== undefined);
  return frames.length > 1 ? frames : undefined;
}

function appendUnique(lines: string[], seen: Set<string>, line: string, maxLines: number) {
  const signature = line
    .replace(/\bref=[^\s\]]+\s*/g, "")
    .replace(/\[\s*\]/g, "")
    .trim()
    .toLocaleLowerCase();
  if (!signature || seen.has(signature) || lines.length >= maxLines) return;
  seen.add(signature);
  lines.push(line);
}

function quoted(value: string) {
  return JSON.stringify(truncate(value, 240));
}

function clean(value: unknown) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim() : "";
}

function truncate(value: string, length: number) {
  return value.length <= length ? value : `${value.slice(0, length)}...`;
}

function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.min(max, Math.max(min, number)) : fallback;
}

function numberValue(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) ? number : undefined;
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function asRecord(value: unknown): Record<string, any> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, any>;
}

function removeUndefined<T extends Record<string, unknown>>(value: T) {
  return Object.fromEntries(Object.entries(value).filter(([, item]) => item !== undefined));
}
