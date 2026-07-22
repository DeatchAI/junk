import { readFile, stat } from "node:fs/promises";
import { basename, delimiter, resolve, sep } from "node:path";

import { BrowserBridge, type BrowserCommandEnvelope } from "./BrowserBridge";
import { BrowserCodeExecutor } from "./BrowserCodeExecutor";
import { compactBrowserSnapshot } from "./BrowserSnapshot";
import { PowerBrowserActor, type PowerBrowserSettings } from "./PowerBrowserActor";

export type BrowserAutomationMode = "signed_in" | "power";

export interface BrowserAutomationSettings extends PowerBrowserSettings {
  mode: BrowserAutomationMode;
}

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

const DEFAULT_SETTINGS: BrowserAutomationSettings = {
  mode: "signed_in",
  headless: false,
  viewportWidth: 1280,
  viewportHeight: 800,
};
const BROWSER_HARNESS_VERSION = "0.3.5";

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
const CODE_SCREENSHOT_OPERATIONS = new Set(["navigate", "open_tab", "click", "key", "select", "upload_file"]);
const MAX_TRAJECTORY_SCREENSHOTS = 4;

export class BrowserAutomation {
  private settings = { ...DEFAULT_SETTINGS };
  private readonly power = new PowerBrowserActor(DEFAULT_SETTINGS);
  private readonly taskModes = new Map<string, BrowserAutomationMode>();
  private readonly taskUploadRoots = new Map<string, string[]>();
  private readonly artifacts = new Map<string, BrowserArtifacts>();

  constructor(private readonly extension: BrowserBridge) {}

  updateSettings(next: Partial<BrowserAutomationSettings>) {
    const previousMode = this.settings.mode;
    const sanitized: Partial<BrowserAutomationSettings> = {};
    if (next.mode === "power" || next.mode === "signed_in") sanitized.mode = next.mode;
    if (typeof next.cdpUrl === "string") sanitized.cdpUrl = next.cdpUrl.trim() || undefined;
    if (typeof next.userDataDir === "string") sanitized.userDataDir = next.userDataDir.trim() || undefined;
    if (typeof next.headless === "boolean") sanitized.headless = next.headless;
    if (typeof next.viewportWidth === "number") sanitized.viewportWidth = next.viewportWidth;
    if (typeof next.viewportHeight === "number") sanitized.viewportHeight = next.viewportHeight;
    const mode = sanitized.mode ?? this.settings.mode;
    this.settings = {
      ...this.settings,
      ...sanitized,
      mode,
      viewportWidth: clampNumber(sanitized.viewportWidth, 800, 3840, this.settings.viewportWidth),
      viewportHeight: clampNumber(sanitized.viewportHeight, 600, 2160, this.settings.viewportHeight),
    };
    this.power.updateSettings(this.settings);
    if (previousMode === "power" && mode === "signed_in" && ![...this.taskModes.values()].includes("power")) {
      void this.power.stop();
    }
    return this.getSettings();
  }

  getSettings() {
    return { ...this.settings };
  }

  async getStatus() {
    const extension = this.extension.getStatus();
    return {
      harnessVersion: BROWSER_HARNESS_VERSION,
      mode: this.settings.mode,
      ...extension,
      extension,
      power: await this.power.status(),
    };
  }

  async beginTask(runId: string, allowedUploadPaths: string[] = []) {
    const mode = this.settings.mode;
    this.taskModes.set(runId, mode);
    this.artifacts.set(runId, { trace: [], screenshots: [] });
    this.taskUploadRoots.set(runId, uniqueResolvedPaths([
      ...allowedUploadPaths,
      ...(Bun.env.DETACH_BROWSER_UPLOAD_ROOTS?.split(delimiter) ?? []),
    ]));
    if (mode === "power") {
      await this.power.beginTask(runId);
    } else {
      const status = this.extension.getStatus();
      if (!status.extensionConnected) {
        throw new Error("Signed-in Chrome is selected, but the Detach Browser Agent extension is not connected. Open its popup or choose Power Browser in Settings.");
      }
      await this.extension.execute({ command: "browser.begin_task", payload: { runId, isolated: false } });
    }
  }

  async getTaskContext(runId: string) {
    const mode = this.taskModes.get(runId);
    if (!mode) return undefined;
    const tab = asRecord(await this.executeUntraced({ command: "browser.get_active_tab", payload: {} }, runId, mode));
    return {
      url: typeof tab.url === "string" ? tab.url : undefined,
      title: typeof tab.title === "string" ? tab.title : undefined,
      tabId: typeof tab.id === "string" || typeof tab.id === "number" ? tab.id : undefined,
    };
  }

  async endTask(runId: string, captureFinal = true) {
    const mode = this.taskModes.get(runId);
    if (!mode) return;
    const artifacts = this.ensureArtifacts(runId);
    if (captureFinal) {
      try {
        const snapshot = await this.executeUntraced({
          command: "browser.snapshot",
          payload: { maxElements: 200, maxTextLength: 12_000 },
        }, runId, mode);
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
        const screenshot = await this.executeUntraced({ command: "browser.screenshot", payload: { format: "jpeg", quality: 75 } }, runId, mode);
        const data = screenshotData(screenshot);
        if (data) artifacts.finalScreenshot = data;
      } catch {
        // Restricted and credential-filled pages intentionally block screenshots.
      }
    }

    if (mode === "power") {
      await this.power.endTask(runId);
    } else if (this.extension.getStatus().extensionConnected) {
      await this.extension.execute({ command: "browser.end_task", payload: { runId } }).catch(() => undefined);
    }
    artifacts.completedAt = Date.now();
    this.taskModes.delete(runId);
    this.taskUploadRoots.delete(runId);
    if (mode === "power" && this.settings.mode === "signed_in" && ![...this.taskModes.values()].includes("power")) {
      await this.power.stop();
    }
    this.pruneArtifacts();
  }

  async execute(envelope: BrowserCommandEnvelope, runId?: string) {
    const command = envelope.command?.trim();
    if (!command) throw new Error("Browser command is required");
    const mode = runId ? this.taskModes.get(runId) ?? this.settings.mode : this.settings.mode;
    const startedAt = Date.now();
    const args = await this.normalizePayload(command, envelope.payload ?? {}, mode, runId);
    const trace: BrowserTraceEntry = {
      id: `browser_trace_${crypto.randomUUID()}`,
      runId,
      command,
      engine: mode,
      startedAt,
      durationMs: 0,
      ok: false,
      args: redactArgs(args),
    };

    try {
      const result = command === "browser.execute_code"
        ? await this.executeCode(args, runId, mode)
        : await this.executeUntraced({ command, payload: args }, runId, mode);
      trace.ok = true;
      trace.result = summarizeResult(result);
      const images = screenshotDataList(result);
      if (runId && images.length > 0) {
        const artifacts = this.ensureArtifacts(runId);
        artifacts.screenshots.push(...images.slice(0, Math.max(0, MAX_TRAJECTORY_SCREENSHOTS - artifacts.screenshots.length)));
      } else if (runId && shouldCaptureAfter(command, result)) {
        await this.captureArtifactScreenshot(runId, mode);
      }
      return attachMetadata(result, {
        traceId: trace.id,
        engine: mode,
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
    for (const runId of [...this.taskModes.keys()]) {
      await this.endTask(runId).catch(() => undefined);
    }
    await this.power.stop();
  }

  private async executeUntraced(envelope: BrowserCommandEnvelope, runId: string | undefined, mode: BrowserAutomationMode) {
    if (mode === "power") return await this.power.execute(envelope.command, envelope.payload, runId);
    return await this.extension.execute({
      command: envelope.command,
      payload: { ...(envelope.payload ?? {}), ...(runId ? { runId } : {}) },
    });
  }

  private async executeCode(payload: Record<string, unknown>, runId: string | undefined, mode: BrowserAutomationMode) {
    const code = typeof payload.code === "string" ? payload.code : "";
    const timeoutMs = clampNumber(payload.timeoutMs, 1_000, 300_000, 60_000);
    const executor = new BrowserCodeExecutor(async (command, commandPayload) => {
      const normalized = await this.normalizePayload(command, commandPayload, mode, runId);
      return await this.executeUntraced({ command, payload: normalized }, runId, mode);
    });
    return await executor.execute(code, timeoutMs);
  }

  private async normalizePayload(command: string, payload: Record<string, unknown>, mode: BrowserAutomationMode, runId?: string) {
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
    if (mode === "power") return payload;

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

  private async captureArtifactScreenshot(runId: string, mode: BrowserAutomationMode) {
    const artifacts = this.ensureArtifacts(runId);
    if (artifacts.screenshots.length >= MAX_TRAJECTORY_SCREENSHOTS) return;
    try {
      const screenshot = await this.executeUntraced({
        command: "browser.screenshot",
        payload: { format: "jpeg", quality: 65 },
      }, runId, mode);
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
