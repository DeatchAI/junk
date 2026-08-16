import { readFile, stat } from "node:fs/promises";
import { basename, delimiter, resolve, sep } from "node:path";

import { BrowserBridge, type BrowserCommandEnvelope } from "./BrowserBridge";
import {
  BrowserCodeExecutor,
  type BrowserPrimitiveUpdate,
} from "./BrowserCodeExecutor";
import { compactBrowserSnapshot } from "./BrowserSnapshot";
import { DocumentArtifactService } from "./DocumentArtifactService";
import type { AgentActivityAction } from "../protocol/messages";

export type BrowserAutomationMode = "signed_in";

export interface BrowserTraceEntry {
  id: string;
  runId?: string;
  command: string;
  engine: BrowserAutomationMode;
  startedAt: number;
  durationMs: number;
  ok: boolean;
  args: Record<string, unknown>;
  result?: unknown;
  error?: string;
}

export interface BrowserArtifacts {
  trace: BrowserTraceEntry[];
  screenshots: string[];
  finalState?: unknown;
  finalScreenshot?: string;
  completedAt?: number;
}

export interface BrowserActivityUpdate {
  id: string;
  action: AgentActivityAction;
  phase: "started" | "completed" | "failed";
  title: string;
  subtitle?: string;
  sourceEventType: string;
}

export type BrowserActivitySink = (update: BrowserActivityUpdate) => void;

const BROWSER_HARNESS_VERSION = "0.4.0";

const ARTIFACT_SCREENSHOT_COMMANDS = new Set([
  "browser.open_tab",
  "browser.navigate",
  "browser.back",
  "browser.forward",
  "browser.refresh",
  "browser.click",
  "browser.key",
  "browser.select",
  "browser.upload_file",
]);
const CODE_SCREENSHOT_OPERATIONS = new Set([
  "navigate",
  "open_tab",
  "click",
  "key",
  "check",
  "drag",
  "select",
  "upload_file",
  "media",
]);
const MAX_TRAJECTORY_SCREENSHOTS = 4;

export class BrowserAutomation {
  private readonly activeTasks = new Set<string>();
  private readonly taskUploadRoots = new Map<string, string[]>();
  private readonly activitySinks = new Map<string, BrowserActivitySink>();
  private readonly artifacts = new Map<string, BrowserArtifacts>();
  private readonly documents = new DocumentArtifactService();

  constructor(private readonly extension: BrowserBridge) {}

  async getStatus() {
    const extension = this.extension.getStatus();
    return {
      harnessVersion: BROWSER_HARNESS_VERSION,
      mode: "signed_in" as const,
      ...extension,
      extension,
      activeTasks: this.activeTasks.size,
    };
  }

  async beginTask(
    runId: string,
    allowedUploadPaths: string[] = [],
    activitySink?: BrowserActivitySink,
  ) {
    this.activeTasks.add(runId);
    this.artifacts.set(runId, { trace: [], screenshots: [] });
    if (activitySink) this.activitySinks.set(runId, activitySink);
    this.taskUploadRoots.set(runId, uniqueResolvedPaths([
      ...allowedUploadPaths,
      ...(Bun.env.DETACH_BROWSER_UPLOAD_ROOTS?.split(delimiter) ?? []),
    ]));
    const status = this.extension.getStatus();
    if (!status.extensionConnected) {
      this.activeTasks.delete(runId);
      this.activitySinks.delete(runId);
      throw new Error("The Detach Browser Agent extension is not connected. Open its popup in signed-in Chrome.");
    }
    try {
      await this.extension.execute({ command: "browser.begin_task", payload: { runId } });
    } catch (error) {
      this.activeTasks.delete(runId);
      this.artifacts.delete(runId);
      this.taskUploadRoots.delete(runId);
      this.activitySinks.delete(runId);
      throw error;
    }
  }

  async getTaskContext(runId: string) {
    if (!this.activeTasks.has(runId)) return undefined;
    const tab = asRecord(await this.executeUntraced({ command: "browser.get_active_tab", payload: {} }, runId));
    return {
      url: typeof tab.url === "string" ? tab.url : undefined,
      title: typeof tab.title === "string" ? tab.title : undefined,
      tabId: typeof tab.id === "string" || typeof tab.id === "number" ? tab.id : undefined,
    };
  }

  isTaskActive(runId: string) {
    return this.activeTasks.has(runId);
  }

  async endTask(runId: string, captureFinal = true) {
    if (!this.activeTasks.has(runId)) return;
    const artifacts = this.ensureArtifacts(runId);
    if (captureFinal) {
      try {
        const snapshot = await this.executeUntraced({
          command: "browser.snapshot",
          payload: { maxElements: 200, maxTextLength: 12_000 },
        }, runId);
        artifacts.finalState = compactBrowserSnapshot(snapshot, {
          includeText: true,
          includeTables: true,
          maxLines: 160,
          maxTextLength: 8_000,
        });
      } catch {
        // A final screenshot can still provide evidence if semantic inspection is restricted.
      }
      try {
        const screenshot = await this.executeUntraced({ command: "browser.screenshot", payload: { format: "jpeg", quality: 75 } }, runId);
        const data = screenshotData(screenshot);
        if (data) artifacts.finalScreenshot = data;
      } catch {
        // Restricted and credential-filled pages intentionally block screenshots.
      }
    }

    if (this.extension.getStatus().extensionConnected) {
      await this.extension.execute({ command: "browser.end_task", payload: { runId } }).catch(() => undefined);
    }
    artifacts.completedAt = Date.now();
    this.activeTasks.delete(runId);
    this.taskUploadRoots.delete(runId);
    this.activitySinks.delete(runId);
    this.documents.endTask(runId);
    this.pruneArtifacts();
  }

  async execute(envelope: BrowserCommandEnvelope, runId?: string) {
    const command = envelope.command?.trim();
    if (!command) throw new Error("Browser command is required");
    const startedAt = Date.now();
    const args = await this.normalizePayload(command, envelope.payload ?? {}, runId);
    const trace: BrowserTraceEntry = {
      id: `browser_trace_${crypto.randomUUID()}`,
      runId,
      command,
      engine: "signed_in",
      startedAt,
      durationMs: 0,
      ok: false,
      args: redactArgs(args),
    };

    try {
      const result = command === "browser.execute_code"
        ? await this.executeCode(args, runId)
        : await this.executeUntraced({ command, payload: args }, runId);
      trace.ok = true;
      trace.result = summarizeResult(result);
      const images = screenshotDataList(result);
      if (runId && images.length > 0) {
        const artifacts = this.ensureArtifacts(runId);
        artifacts.screenshots.push(...images.slice(0, Math.max(0, MAX_TRAJECTORY_SCREENSHOTS - artifacts.screenshots.length)));
      } else if (runId && shouldCaptureAfter(command, result)) {
        await this.captureArtifactScreenshot(runId);
      }
      return attachMetadata(result, {
        traceId: trace.id,
        engine: "signed_in",
        durationMs: Date.now() - startedAt,
      });
    } catch (error) {
      trace.error = error instanceof Error ? error.message : String(error);
      throw error;
    } finally {
      trace.durationMs = Date.now() - startedAt;
      if (runId) {
        const artifacts = this.ensureArtifacts(runId);
        artifacts.trace.push(trace);
        if (artifacts.trace.length > 300) artifacts.trace.shift();
      }
    }
  }

  getArtifacts(runId: string) {
    const artifacts = this.artifacts.get(runId);
    if (!artifacts) return { trace: [], screenshots: [] };
    return {
      trace: artifacts.trace,
      finalState: artifacts.finalState,
      screenshots: [...artifacts.screenshots, ...(artifacts.finalScreenshot ? [artifacts.finalScreenshot] : [])].slice(-10),
      completedAt: artifacts.completedAt,
    };
  }

  async stop() {
    for (const runId of [...this.activeTasks]) {
      await this.endTask(runId).catch(() => undefined);
    }
    this.documents.clear();
  }

  private async executeUntraced(envelope: BrowserCommandEnvelope, runId?: string) {
    if (envelope.command === "browser.artifact") {
      if (!runId) throw new Error("Document artifacts require an active browser task");
      const fetched = asRecord(await this.extension.execute({
        command: "browser.artifact_fetch",
        payload: { ...(envelope.payload ?? {}), runId },
      }));
      return await this.documents.ingest(runId, {
        url: stringValue(fetched.url) || stringValue(envelope.payload?.url) || "",
        mimeType: stringValue(fetched.mimeType),
        fileName: stringValue(fetched.fileName),
        dataBase64: stringValue(fetched.dataBase64) || "",
      });
    }
    if (envelope.command === "browser.artifacts") {
      if (!runId) throw new Error("Document artifacts require an active browser task");
      const artifactId = stringValue(envelope.payload?.artifactId);
      return artifactId ? this.documents.get(runId, artifactId) : { artifacts: this.documents.list(runId) };
    }
    return await this.extension.execute({
      command: envelope.command,
      payload: { ...(envelope.payload ?? {}), ...(runId ? { runId } : {}) },
    });
  }

  private async executeCode(payload: Record<string, unknown>, runId?: string) {
    const code = typeof payload.code === "string" ? payload.code : "";
    const timeoutMs = clampNumber(payload.timeoutMs, 1_000, 300_000, 60_000);
    const executor = new BrowserCodeExecutor(async (command, commandPayload) => {
      const normalized = await this.normalizePayload(command, commandPayload, runId);
      return await this.executeUntraced({ command, payload: normalized }, runId);
    }, (update) => {
      if (!runId) return;
      this.activitySinks.get(runId)?.(browserActivityForPrimitive(update));
    });
    return await executor.execute(code, timeoutMs);
  }

  private async normalizePayload(command: string, payload: Record<string, unknown>, runId?: string) {
    if (command !== "browser.upload_file") return payload;
    const paths = Array.isArray(payload.paths)
      ? payload.paths.filter((value): value is string => typeof value === "string")
      : typeof payload.path === "string" ? [payload.path] : [];
    if (paths.length === 0) return payload;

    const allowedRoots = runId ? this.taskUploadRoots.get(runId) ?? [] : [];
    for (const requestedPath of paths) {
      const path = resolve(requestedPath);
      if (!allowedRoots.some((root) => path === root || path.startsWith(`${root}${sep}`))) {
        throw new Error(`Upload path is not attached to this task or inside its workspace: ${basename(path)}`);
      }
    }
    const files: Array<{ name: string; dataBase64: string; type: string }> = [];
    for (const requestedPath of paths) {
      const path = resolve(requestedPath);
      const info = await stat(path);
      if (!info.isFile()) throw new Error(`Upload path is not a file: ${path}`);
      if (info.size > 10 * 1024 * 1024) throw new Error(`Upload file is larger than 10 MB: ${basename(path)}`);
      files.push({
        name: basename(path),
        dataBase64: Buffer.from(await readFile(path)).toString("base64"),
        type: stringValue(payload.mimeType) || guessMimeType(path),
      });
    }
    return { ...payload, files };
  }

  private ensureArtifacts(runId: string) {
    let artifacts = this.artifacts.get(runId);
    if (!artifacts) {
      artifacts = { trace: [], screenshots: [] };
      this.artifacts.set(runId, artifacts);
    }
    return artifacts;
  }

  private async captureArtifactScreenshot(runId: string) {
    const artifacts = this.ensureArtifacts(runId);
    if (artifacts.screenshots.length >= MAX_TRAJECTORY_SCREENSHOTS) return;
    try {
      const screenshot = await this.executeUntraced({
        command: "browser.screenshot",
        payload: { format: "jpeg", quality: 65 },
      }, runId);
      const image = screenshotData(screenshot);
      if (image) artifacts.screenshots.push(image);
    } catch {
      // Screenshot restrictions should not turn a successful action into a failure.
    }
  }

  private pruneArtifacts() {
    if (this.artifacts.size <= 30) return;
    const completed = [...this.artifacts.entries()]
      .filter(([, value]) => value.completedAt)
      .sort((a, b) => (a[1].completedAt ?? 0) - (b[1].completedAt ?? 0));
    for (const [runId] of completed.slice(0, Math.max(0, this.artifacts.size - 30))) this.artifacts.delete(runId);
  }
}

export function browserActivityForPrimitive(update: BrowserPrimitiveUpdate): BrowserActivityUpdate {
  const action = browserAction(update.command);
  const target = browserTarget(update.command, update.payload);
  const title = browserTitle(update.command, target);
  return {
    id: update.id,
    action: update.phase === "failed" ? "error" : action,
    phase: update.phase,
    title,
    subtitle: update.phase === "failed" ? conciseError(update.error) : target?.subtitle,
    sourceEventType: update.command,
  };
}

function browserAction(command: string): AgentActivityAction {
  if (/(navigate|open_tab|back|forward|refresh|activate_tab|close_tab)/.test(command)) return "browser.navigate";
  if (/(snapshot|extract_text|list_tabs|get_active_tab|frames|resolve_frame|table|url|title)/.test(command)) return "browser.inspect";
  if (/(type|fill|key|press|select|check|uncheck)/.test(command)) return "browser.type";
  if (/(screenshot|media|frame|caption)/.test(command)) return "browser.capture";
  if (/(wait|events)/.test(command)) return "wait";
  if (/(upload)/.test(command)) return "image";
  return "browser.interact";
}

function browserTarget(command: string, payload: Record<string, unknown>) {
  const rawURL = typeof payload.url === "string" ? payload.url : undefined;
  if (rawURL) {
    try {
      const url = new URL(rawURL);
      return { label: url.hostname || "the page", subtitle: url.hostname || undefined };
    } catch {
      return { label: "the page" };
    }
  }

  const name = safeLabel(payload.name)
    ?? safeLabel(payload.accessibleName)
    ?? safeLabel(payload.label)
    ?? safeLabel(payload.placeholder);
  return name ? { label: `“${name}”` } : undefined;
}

function browserTitle(command: string, target?: { label: string }) {
  const label = target?.label;
  if (command === "browser.navigate") return label ? `Opening ${label}` : "Opening a web page";
  if (command === "browser.open_tab") return label ? `Opening ${label} in a new tab` : "Opening a browser tab";
  if (command === "browser.back") return "Going back in the browser";
  if (command === "browser.forward") return "Going forward in the browser";
  if (command === "browser.refresh") return "Refreshing the current page";
  if (command === "browser.list_tabs") return "Reviewing open browser tabs";
  if (command === "browser.get_active_tab") return "Checking the active browser tab";
  if (command === "browser.snapshot") return "Inspecting the current page";
  if (command === "browser.extract_text") return "Reading the current page";
  if (command === "browser.screenshot") return "Capturing browser evidence";
  if (command === "browser.click") return label ? `Clicking ${label}` : "Clicking in the browser";
  if (command === "browser.hover") return label ? `Inspecting ${label}` : "Inspecting a browser control";
  if (/(type|fill)/.test(command)) return label ? `Entering text in ${label}` : "Entering text in the browser";
  if (/(key|press)/.test(command)) return "Using the browser keyboard";
  if (command === "browser.select") return label ? `Selecting ${label}` : "Selecting a browser option";
  if (command === "browser.upload_file") return "Uploading a file";
  if (/(wait)/.test(command)) return "Waiting for the page to update";
  if (command === "browser.artifact") return "Reading a browser document";
  return humanizeBrowserCommand(command);
}

function safeLabel(value: unknown) {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim().replace(/\s+/g, " ");
  if (!trimmed || trimmed.length > 60) return undefined;
  return trimmed;
}

function humanizeBrowserCommand(command: string) {
  const value = command
    .replace(/^browser\./, "")
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
  return `${value || "Using browser"}`;
}

function conciseError(error?: string) {
  if (!error) return undefined;
  const firstLine = error.trim().split(/\r?\n/)[0] ?? "";
  return firstLine.length <= 120 ? firstLine : `${firstLine.slice(0, 117)}...`;
}

function uniqueResolvedPaths(values: string[]) {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean).map((value) => resolve(value)))];
}

function shouldCaptureAfter(command: string, result: unknown) {
  if (ARTIFACT_SCREENSHOT_COMMANDS.has(command)) return true;
  if (command !== "browser.execute_code") return false;
  const operations = asRecord(result).operations;
  return Array.isArray(operations) && operations.some((operation) => {
    const record = asRecord(operation);
    return record.ok === true && CODE_SCREENSHOT_OPERATIONS.has(String(record.operation || ""));
  });
}

function attachMetadata(result: unknown, metadata: Record<string, unknown>) {
  if (result && typeof result === "object" && !Array.isArray(result)) {
    return { ...(result as Record<string, unknown>), _detach: metadata };
  }
  return { value: result, _detach: metadata };
}

function screenshotData(result: unknown) {
  const record = asRecord(result);
  if (typeof record.data === "string" && record.data) return record.data;
  if (typeof record.dataUrl !== "string") return undefined;
  return record.dataUrl.match(/^data:image\/[^;]+;base64,(.+)$/s)?.[1];
}

function screenshotDataList(result: unknown) {
  const direct = screenshotData(result);
  const record = asRecord(result);
  const images = Array.isArray(record.images)
    ? record.images.map(asRecord).map((image) => typeof image.data === "string" ? image.data : undefined).filter((data): data is string => Boolean(data))
    : [];
  return [...(direct ? [direct] : []), ...images];
}

function summarizeResult(value: unknown): unknown {
  const record = asRecord(value);
  if (Object.keys(record).length === 0) return value;
  if (record.data || record.dataUrl) {
    return { format: record.format, mimeType: record.mimeType, screenshot: true, tab: record.tab };
  }
  if (Array.isArray(record.operations)) {
    return {
      operations: record.operations.slice(0, 100),
      failedOperations: record.operations.filter((operation: unknown) => asRecord(operation).ok === false).length,
      events: Array.isArray(record.events) ? record.events.slice(-50) : [],
      screenshots: Array.isArray(record.images) ? record.images.length : 0,
      result: summarizeCodeResult(record.result),
    };
  }
  if (Array.isArray(record.elements)) {
    return {
      url: record.url,
      title: record.title,
      readyState: record.readyState,
      elements: record.elements.length,
      changed: asRecord(record.delta).changed?.length,
      textLength: typeof record.text === "string" ? record.text.length : undefined,
    };
  }
  const serialized = JSON.stringify(value);
  return serialized.length <= 4_000 ? value : { summary: `${serialized.slice(0, 4_000)}...`, truncated: true };
}

function summarizeCodeResult(value: unknown) {
  const serialized = JSON.stringify(value);
  if (!serialized || serialized.length <= 8_000) return value;
  return `${serialized.slice(0, 8_000)}...`;
}

function redactArgs(value: Record<string, unknown>) {
  const copy = { ...value };
  if (typeof copy.code === "string" && copy.code.length > 4_000) copy.code = `${copy.code.slice(0, 4_000)}...`;
  if (typeof copy.inputText === "string" && copy.inputText.length > 500) copy.inputText = `${copy.inputText.slice(0, 500)}...`;
  if (typeof copy.content === "string" && copy.content.length > 500) copy.content = `${copy.content.slice(0, 500)}...`;
  if (Array.isArray(copy.files)) copy.files = copy.files.map((file) => ({ name: asRecord(file).name, type: asRecord(file).type }));
  return copy;
}

function guessMimeType(path: string) {
  const extension = path.split(".").at(-1)?.toLowerCase();
  const types: Record<string, string> = {
    txt: "text/plain", csv: "text/csv", json: "application/json", pdf: "application/pdf",
    png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp",
  };
  return types[extension || ""] || "application/octet-stream";
}

function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.min(max, Math.max(min, number)) : fallback;
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function asRecord(value: unknown): Record<string, any> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, any>;
}
