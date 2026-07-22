import { mkdir, mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { basename, join, resolve } from "node:path";

import { CDPConnection, type CDPEvent } from "./CDPConnection";

export interface PowerBrowserSettings {
  cdpUrl?: string;
  headless: boolean;
  viewportWidth: number;
  viewportHeight: number;
  userDataDir?: string;
}

interface ElementReference {
  backendNodeId: number;
  targetId: string;
}

interface TargetSession {
  targetId: string;
  sessionId: string;
}

interface PowerTask {
  runId: string;
  browserContextId?: string;
  targets: Map<string, TargetSession>;
  activeTargetId: string;
  refs: Map<string, ElementReference>;
  refAliases: Map<string, string>;
  nextRef: number;
  previousElements: Map<string, Map<string, string>>;
  snapshotVersions: Map<string, number>;
  temporaryFiles: Set<string>;
  temporaryDirectories: Set<string>;
  events: BrowserEvent[];
  pendingDialogs: Set<string>;
  frameIds: Set<string>;
}

export interface BrowserEvent {
  type: "popup" | "new_tab" | "dialog" | "download" | "navigation" | "failure" | "tab_closed";
  timestamp: number;
  tabId?: string;
  url?: string;
  [key: string]: unknown;
}

type BrowserProcess = ReturnType<typeof Bun.spawn>;

const DEFAULT_TASK = "detach-default-browser-task";
const MAX_SNAPSHOT_ELEMENTS = 240;

export class PowerBrowserActor {
  private settings: PowerBrowserSettings;
  private connection?: CDPConnection;
  private process?: BrowserProcess;
  private launchedProfileDir?: string;
  private ownsLaunchedProfile = false;
  private tasks = new Map<string, PowerTask>();
  private starting?: Promise<void>;
  private stopping?: Promise<void>;
  private inflightRequests = new Map<string, number>();
  private lastNetworkActivity = new Map<string, number>();
  private targetAttachments = new Map<string, Promise<TargetSession>>();
  private downloadTasks = new Map<string, string>();

  constructor(settings?: Partial<PowerBrowserSettings>) {
    this.settings = {
      headless: false,
      viewportWidth: 1280,
      viewportHeight: 800,
      ...settings,
    };
  }

  updateSettings(settings: Partial<PowerBrowserSettings>) {
    const next = { ...this.settings, ...settings };
    const shouldRestart = Boolean(this.connection) && (
      next.cdpUrl !== this.settings.cdpUrl
      || next.headless !== this.settings.headless
      || next.viewportWidth !== this.settings.viewportWidth
      || next.viewportHeight !== this.settings.viewportHeight
      || next.userDataDir !== this.settings.userDataDir
    );
    this.settings = next;
    if (shouldRestart) void this.stop();
  }

  async beginTask(runId: string) {
    await this.ensureTask(runId);
  }

  async endTask(runId: string) {
    const task = this.tasks.get(runId);
    if (!task) return;
    this.tasks.delete(runId);

    if (task.browserContextId && this.connection) {
      await this.connection.send("Target.disposeBrowserContext", {
        browserContextId: task.browserContextId,
      }).catch(() => undefined);
    } else if (this.connection) {
      for (const targetId of task.targets.keys()) {
        await this.connection.send("Target.closeTarget", { targetId }).catch(() => undefined);
      }
    }

    for (const file of task.temporaryFiles) {
      await rm(file, { force: true }).catch(() => undefined);
    }
    for (const directory of task.temporaryDirectories) {
      await rm(directory, { recursive: true, force: true }).catch(() => undefined);
    }
  }

  async stop() {
    if (this.stopping) return await this.stopping;
    this.stopping = this.stopNow().finally(() => {
      this.stopping = undefined;
    });
    return await this.stopping;
  }

  private async stopNow() {
    const tasks = [...this.tasks.keys()];
    for (const runId of tasks) await this.endTask(runId);
    this.connection?.close();
    this.connection = undefined;
    if (this.process) {
      const process = this.process;
      process.kill();
      await Promise.race([process.exited.catch(() => undefined), Bun.sleep(2_000)]);
      this.process = undefined;
    }
    if (this.ownsLaunchedProfile && this.launchedProfileDir) {
      await rm(this.launchedProfileDir, { recursive: true, force: true }).catch(() => undefined);
    }
    this.launchedProfileDir = undefined;
    this.ownsLaunchedProfile = false;
    this.starting = undefined;
    this.inflightRequests.clear();
    this.lastNetworkActivity.clear();
    this.targetAttachments.clear();
    this.downloadTasks.clear();
  }

  async status() {
    const executable = this.settings.cdpUrl ? undefined : await findChromiumExecutable();
    return {
      engine: "cdp",
      available: Boolean(this.settings.cdpUrl || executable),
      connected: Boolean(this.connection),
      launchedByDetach: Boolean(this.process),
      browser: this.settings.cdpUrl ? "attached Chromium" : "isolated Chromium",
      executable,
      persistentProfile: !this.settings.cdpUrl,
      profileDirectory: this.settings.cdpUrl ? undefined : this.launchedProfileDir
        || this.settings.userDataDir?.trim()
        || defaultPowerProfileDirectory(),
      headless: this.settings.headless,
      viewport: {
        width: this.settings.viewportWidth,
        height: this.settings.viewportHeight,
      },
      activeTasks: this.tasks.size,
    };
  }

  async execute(command: string, payload: Record<string, unknown> = {}, runId?: string): Promise<unknown> {
    const task = await this.ensureTask(runId || DEFAULT_TASK);
    try {
      return await this.executeForTask(task, command, payload);
    } catch (error) {
      this.pushEvent(task, {
        type: "failure",
        command,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  private async executeForTask(task: PowerTask, command: string, payload: Record<string, unknown>): Promise<unknown> {
    switch (command) {
      case "browser.status":
        return { ...(await this.status()), activeTab: await this.activeTab(task) };
      case "browser.list_tabs":
        return await this.listTabs(task);
      case "browser.get_active_tab":
        return await this.activeTab(task);
      case "browser.open_tab":
        return await this.openTab(task, payload);
      case "browser.navigate":
        return await this.navigate(task, payload);
      case "browser.snapshot":
        return await this.snapshot(task, payload);
      case "browser.extract_text":
        return await this.extractText(task, payload);
      case "browser.query":
        return await this.query(task, payload);
      case "browser.get_selection":
        return await this.evaluateValue(task, payload, "String(window.getSelection() || '')");
      case "browser.click":
        return await this.click(task, payload);
      case "browser.type":
        return await this.type(task, payload);
      case "browser.dropdown_options":
        return await this.dropdownOptions(task, payload);
      case "browser.select":
        return await this.select(task, payload);
      case "browser.upload_file":
        return await this.uploadFile(task, payload);
      case "browser.key":
        return await this.key(task, payload);
      case "browser.hover":
        return await this.hover(task, payload);
      case "browser.scroll":
        return await this.scroll(task, payload);
      case "browser.wait":
        return await this.wait(task, payload);
      case "browser.back":
        return await this.history(task, payload, -1);
      case "browser.forward":
        return await this.history(task, payload, 1);
      case "browser.refresh":
        return await this.refresh(task, payload);
      case "browser.activate_tab":
        return await this.activateTab(task, payload);
      case "browser.close_tab":
        return await this.closeTab(task, payload);
      case "browser.screenshot":
        return await this.screenshot(task, payload);
      case "browser.events":
        return this.readEvents(task, payload.drain !== false);
      case "browser.dialog":
        return await this.handleDialog(task, payload);
      default:
        throw new Error(`Unsupported Power browser command: ${command}`);
    }
  }

  private async ensureTask(runId: string) {
    const existing = this.tasks.get(runId);
    if (existing) return existing;
    await this.ensureStarted();
    const connection = this.requireConnection();

    let browserContextId: string | undefined;
    if (this.settings.cdpUrl) {
      try {
        const context = await connection.send("Target.createBrowserContext", { disposeOnDetach: true });
        browserContextId = context.browserContextId;
      } catch {
        // Some externally supplied CDP endpoints expose only the default context.
      }
    }

    const created = await connection.send("Target.createTarget", {
      url: "about:blank",
      ...(browserContextId ? { browserContextId } : {}),
      width: this.settings.viewportWidth,
      height: this.settings.viewportHeight,
    });
    const targetId = requireString(created.targetId, "CDP target id");
    const target = await this.ensureAttachedTarget(targetId);
    const task: PowerTask = {
      runId,
      browserContextId,
      targets: new Map([[targetId, target]]),
      activeTargetId: targetId,
      refs: new Map(),
      refAliases: new Map(),
      nextRef: 1,
      previousElements: new Map(),
      snapshotVersions: new Map(),
      temporaryFiles: new Set(),
      temporaryDirectories: new Set(),
      events: [],
      pendingDialogs: new Set(),
      frameIds: new Set(),
    };
    this.tasks.set(runId, task);
    const downloadDir = await mkdtemp(join(tmpdir(), "detach-browser-download-"));
    task.temporaryDirectories.add(downloadDir);
    await connection.send("Browser.setDownloadBehavior", {
      behavior: "allowAndName",
      downloadPath: downloadDir,
      eventsEnabled: true,
      ...(browserContextId ? { browserContextId } : {}),
    }).catch(() => undefined);
    return task;
  }

  private async ensureStarted() {
    if (this.stopping) await this.stopping;
    if (this.connection) return;
    if (this.starting) return await this.starting;
    this.starting = this.start().finally(() => {
      this.starting = undefined;
    });
    return await this.starting;
  }

  private async start() {
    try {
      let websocketUrl = this.settings.cdpUrl?.trim();
      if (!websocketUrl) websocketUrl = await this.launchBrowser();
      this.connection = await connectCDPWithRetry(websocketUrl);
      this.connection.onEvent((event) => this.handleEvent(event));
      await this.connection.send("Target.setDiscoverTargets", { discover: true }).catch(() => undefined);
    } catch (error) {
      await this.stop();
      throw error;
    }
  }

  private async launchBrowser() {
    const executable = await findChromiumExecutable();
    if (!executable) {
      throw new Error("Power browser needs Google Chrome, Brave, Edge, or Chromium installed.");
    }

    const configuredProfile = this.settings.userDataDir?.trim();
    const profileDir = configuredProfile || defaultPowerProfileDirectory();
    await mkdir(profileDir, { recursive: true });
    this.launchedProfileDir = profileDir;
    this.ownsLaunchedProfile = false;

    const args = [
      "--remote-debugging-port=0",
      "--remote-allow-origins=*",
      `--user-data-dir=${profileDir}`,
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-background-networking",
      "--disable-component-update",
      `--window-size=${this.settings.viewportWidth},${this.settings.viewportHeight}`,
      "--no-startup-window",
    ];
    if (this.settings.headless) args.unshift("--headless=new");

    this.process = Bun.spawn([executable, ...args], {
      stdout: "ignore",
      stderr: "pipe",
    });

    const portFile = join(profileDir, "DevToolsActivePort");
    const deadline = Date.now() + 15_000;
    let lastError = "";
    while (Date.now() < deadline) {
      if (this.process.exitCode !== null) {
        const stderr = this.process.stderr instanceof ReadableStream
          ? await new Response(this.process.stderr).text().catch(() => "")
          : "";
        throw new Error(`Power browser exited while starting${stderr.trim() ? `: ${stderr.trim()}` : ""}`);
      }
      try {
        const [port, path] = (await readFile(portFile, "utf8")).trim().split(/\r?\n/);
        if (port && path) {
          const response = await fetch(`http://127.0.0.1:${port}/json/version`);
          const version = asRecord(await response.json());
          const websocketUrl = stringValue(version.webSocketDebuggerUrl);
          if (response.ok && websocketUrl) return websocketUrl;
        }
      } catch (error) {
        lastError = error instanceof Error ? error.message : String(error);
      }
      await Bun.sleep(100);
    }
    throw new Error(`Power browser did not expose its debugging endpoint${lastError ? ` (${lastError})` : ""}`);
  }

  private handleEvent(event: CDPEvent) {
    const sessionId = event.sessionId;
    if (sessionId && event.method === "Network.requestWillBeSent") {
      this.inflightRequests.set(sessionId, (this.inflightRequests.get(sessionId) ?? 0) + 1);
      this.lastNetworkActivity.set(sessionId, Date.now());
    }
    if (sessionId && (event.method === "Network.loadingFinished" || event.method === "Network.loadingFailed")) {
      this.inflightRequests.set(sessionId, Math.max(0, (this.inflightRequests.get(sessionId) ?? 1) - 1));
      this.lastNetworkActivity.set(sessionId, Date.now());
    }
    void this.handleTaskEvent(event);
  }

  private async handleTaskEvent(event: CDPEvent) {
    if (event.method === "Target.targetCreated") {
      const info = asRecord(event.params.targetInfo);
      const targetId = stringValue(info.targetId);
      if (!targetId || info.type !== "page") return;
      const task = [...this.tasks.values()].find((candidate) =>
        (candidate.browserContextId && candidate.browserContextId === info.browserContextId)
        || (typeof info.openerId === "string" && candidate.targets.has(info.openerId))
      );
      if (!task || task.targets.has(targetId)) return;
      try {
        const target = await this.ensureAttachedTarget(targetId);
        task.targets.set(targetId, target);
        task.activeTargetId = targetId;
        this.pushEvent(task, {
          type: typeof info.openerId === "string" ? "popup" : "new_tab",
          tabId: targetId,
          openerTabId: info.openerId,
          url: stringValue(info.url),
          title: stringValue(info.title),
        });
      } catch (error) {
        this.pushEvent(task, { type: "failure", tabId: targetId, error: error instanceof Error ? error.message : String(error) });
      }
      return;
    }

    if (event.method === "Target.targetDestroyed") {
      const targetId = stringValue(event.params.targetId);
      if (!targetId) return;
      const task = [...this.tasks.values()].find((candidate) => candidate.targets.has(targetId));
      if (!task) return;
      task.targets.delete(targetId);
      task.pendingDialogs.delete(targetId);
      this.pushEvent(task, { type: "tab_closed", tabId: targetId });
      if (task.activeTargetId === targetId) task.activeTargetId = task.targets.keys().next().value ?? "";
      return;
    }

    if (event.method === "Target.targetInfoChanged") {
      const info = asRecord(event.params.targetInfo);
      const targetId = stringValue(info.targetId);
      if (!targetId || info.type !== "page") return;
      const task = [...this.tasks.values()].find((candidate) => candidate.targets.has(targetId));
      if (!task) return;
      const recentTargetEvent = [...task.events].reverse().find((queued) => queued.tabId === targetId && (queued.type === "popup" || queued.type === "new_tab"));
      if (recentTargetEvent && info.url) {
        recentTargetEvent.url = info.url;
        recentTargetEvent.title = info.title;
      }
      return;
    }

    if (event.method === "Browser.downloadWillBegin") {
      const frameId = stringValue(event.params.frameId);
      const task = [...this.tasks.values()].find((candidate) => Boolean(frameId && candidate.frameIds.has(frameId)));
      if (task) {
        const guid = stringValue(event.params.guid);
        if (guid) this.downloadTasks.set(guid, task.runId);
        this.pushEvent(task, {
          type: "download",
          phase: "started",
          guid: event.params.guid,
          url: stringValue(event.params.url),
          suggestedFilename: event.params.suggestedFilename,
        });
      }
      return;
    }

    if (event.method === "Browser.downloadProgress") {
      const guid = stringValue(event.params.guid);
      const task = guid ? this.tasks.get(this.downloadTasks.get(guid) ?? "") : undefined;
      if (task) this.pushEvent(task, {
        type: "download",
        phase: event.params.state,
        guid: event.params.guid,
        receivedBytes: event.params.receivedBytes,
        totalBytes: event.params.totalBytes,
      });
      if (guid && (event.params.state === "completed" || event.params.state === "canceled")) this.downloadTasks.delete(guid);
      return;
    }

    const taskAndTarget = this.taskForSession(event.sessionId);
    if (!taskAndTarget) return;
    const { task, target } = taskAndTarget;
    if (event.method === "Page.frameNavigated") {
      const frame = asRecord(event.params.frame);
      const frameId = stringValue(frame.id);
      if (frameId) task.frameIds.add(frameId);
      if (!frame.parentId) this.pushEvent(task, { type: "navigation", tabId: target.targetId, url: stringValue(frame.url), navigationType: "document" });
      return;
    }
    if (event.method === "Page.navigatedWithinDocument") {
      this.pushEvent(task, { type: "navigation", tabId: target.targetId, url: stringValue(event.params.url), navigationType: "same_document" });
      return;
    }
    if (event.method === "Page.javascriptDialogOpening") {
      task.pendingDialogs.add(target.targetId);
      this.pushEvent(task, {
        type: "dialog",
        tabId: target.targetId,
        dialogType: event.params.type,
        message: event.params.message,
        url: event.params.url,
        hasBrowserHandler: event.params.hasBrowserHandler,
      });
      return;
    }
    if (event.method === "Page.javascriptDialogClosed") {
      task.pendingDialogs.delete(target.targetId);
      return;
    }
    if (event.method === "Network.loadingFailed" && event.params.canceled !== true && event.params.type === "Document") {
      this.pushEvent(task, { type: "failure", tabId: target.targetId, error: event.params.errorText, failureType: "navigation" });
      return;
    }
    if (event.method === "Inspector.targetCrashed") {
      this.pushEvent(task, { type: "failure", tabId: target.targetId, error: "Browser tab crashed", failureType: "crash" });
    }
  }

  private async attachTarget(targetId: string): Promise<TargetSession> {
    const attached = await this.requireConnection().send("Target.attachToTarget", { targetId, flatten: true });
    const sessionId = requireString(attached.sessionId, "CDP session id");
    for (const method of ["Page.enable", "DOM.enable", "Runtime.enable", "Accessibility.enable", "Network.enable", "Inspector.enable"]) {
      await this.requireConnection().send(method, {}, sessionId).catch(() => undefined);
    }
    await this.requireConnection().send("Emulation.setDeviceMetricsOverride", {
      width: this.settings.viewportWidth,
      height: this.settings.viewportHeight,
      deviceScaleFactor: 1,
      mobile: false,
    }, sessionId).catch(() => undefined);
    return { targetId, sessionId };
  }

  private async ensureAttachedTarget(targetId: string) {
    const existing = [...this.tasks.values()].map((task) => task.targets.get(targetId)).find(Boolean);
    if (existing) return existing;
    let pending = this.targetAttachments.get(targetId);
    if (!pending) {
      pending = this.attachTarget(targetId).finally(() => this.targetAttachments.delete(targetId));
      this.targetAttachments.set(targetId, pending);
    }
    return await pending;
  }

  private async listTabs(task: PowerTask) {
    const { targetInfos = [] } = await this.requireConnection().send("Target.getTargets");
    return (targetInfos as Array<Record<string, any>>)
      .filter((target) => target.type === "page" && task.targets.has(String(target.targetId || "")))
      .map((target) => ({
        id: target.targetId,
        active: target.targetId === task.activeTargetId,
        title: target.title || "",
        url: target.url || "",
        status: "complete",
        automatable: true,
        engine: "cdp",
      }));
  }

  private async activeTab(task: PowerTask) {
    const tabs = await this.listTabs(task);
    return tabs.find((tab) => tab.id === task.activeTargetId) ?? tabs[0];
  }

  private async openTab(task: PowerTask, payload: Record<string, unknown>) {
    const url = requireWebUrl(payload.url);
    const result = await this.requireConnection().send("Target.createTarget", {
      url,
      ...(task.browserContextId ? { browserContextId: task.browserContextId } : {}),
      width: this.settings.viewportWidth,
      height: this.settings.viewportHeight,
    });
    const targetId = requireString(result.targetId, "CDP target id");
    task.targets.set(targetId, await this.ensureAttachedTarget(targetId));
    if (payload.active !== false) task.activeTargetId = targetId;
    const readiness = await this.waitForReady(task.targets.get(targetId)!, numberValue(payload.timeoutMs, 15_000));
    const tab = (await this.listTabs(task)).find((candidate) => candidate.id === targetId);
    return { ...tab, readiness };
  }

  private async navigate(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const url = requireWebUrl(payload.url);
    const result = await this.requireConnection().send("Page.navigate", { url }, target.sessionId);
    if (result.errorText) throw new Error(`Navigation failed: ${result.errorText}`);
    const readiness = await this.waitForReady(target, numberValue(payload.timeoutMs, 15_000));
    return { ...(await this.pageState(target)), readiness };
  }

  private async snapshot(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    await this.waitForReady(target, numberValue(payload.timeoutMs, 10_000)).catch(() => undefined);
    const [domSnapshot, axTree, page] = await Promise.all([
      this.requireConnection().send("DOMSnapshot.captureSnapshot", {
        computedStyles: ["display", "visibility", "opacity"],
        includeDOMRects: true,
        includePaintOrder: true,
      }, target.sessionId),
      this.requireConnection().send("Accessibility.getFullAXTree", {}, target.sessionId).catch(() => ({ nodes: [] })),
      this.evaluate(target, SNAPSHOT_PAGE_SCRIPT),
    ]);

    const maxElements = Math.min(MAX_SNAPSHOT_ELEMENTS, Math.max(1, numberValue(payload.maxElements, 180)));
    const elements = parseSemanticElements(domSnapshot, axTree, target.targetId, maxElements);
    for (const element of elements) {
      const rawRef = String(element.ref || "");
      if (!rawRef) continue;
      let alias = task.refAliases.get(rawRef);
      if (!alias) {
        alias = `e${task.nextRef++}`;
        task.refAliases.set(rawRef, alias);
      }
      element.ref = alias;
    }
    for (const element of elements) {
      if (typeof element.parentRef === "string") element.parentRef = task.refAliases.get(element.parentRef);
    }
    for (const [ref, stored] of task.refs) {
      if (stored.targetId === target.targetId) task.refs.delete(ref);
    }
    const previousElements = task.previousElements.get(target.targetId) ?? new Map<string, string>();
    const nextElements = new Map<string, string>();
    for (const element of elements) {
      task.refs.set(element.ref, { backendNodeId: element.backendNodeId, targetId: target.targetId });
      nextElements.set(element.ref, JSON.stringify([element.role, element.name, element.value, element.disabled, element.rect]));
      delete (element as Record<string, unknown>).backendNodeId;
    }

    const changed = elements.filter((element) => previousElements.get(element.ref) !== nextElements.get(element.ref));
    const removedRefs = [...previousElements.keys()].filter((ref) => !nextElements.has(ref));
    task.previousElements.set(target.targetId, nextElements);
    const snapshotVersion = (task.snapshotVersions.get(target.targetId) ?? 0) + 1;
    task.snapshotVersions.set(target.targetId, snapshotVersion);

    const pageValue = asRecord(page);
    const text = String(pageValue.text || "");
    const maxTextLength = Math.max(1_000, Math.min(80_000, numberValue(payload.maxTextLength, 20_000)));
    return {
      engine: "cdp",
      snapshotVersion,
      url: pageValue.url,
      title: pageValue.title,
      readyState: pageValue.readyState,
      viewport: pageValue.viewport,
      meta: pageValue.meta,
      text: truncate(text, maxTextLength),
      textTruncated: text.length > maxTextLength,
      elements,
      hierarchy: elements.map((element) => ({ ref: element.ref, parentRef: element.parentRef, depth: element.depth })),
      tables: pageValue.tables,
      delta: {
        changed,
        removedRefs,
        unchangedCount: Math.max(0, elements.length - changed.length),
      },
    };
  }

  private async extractText(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const result = asRecord(await this.evaluate(target, SNAPSHOT_PAGE_SCRIPT));
    const text = String(result.text || "");
    const maxLength = Math.max(1_000, Math.min(80_000, numberValue(payload.maxLength, 20_000)));
    return { text: truncate(text, maxLength), truncated: text.length > maxLength, url: result.url, title: result.title };
  }

  private async query(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const kind = stringValue(payload.kind) || "all";
    const ref = stringValue(payload.ref);
    if (ref) {
      const stored = task.refs.get(ref);
      if (!stored || stored.targetId !== target.targetId) {
        if (kind === "count") return { count: 0 };
        if (kind === "textContent" || kind === "innerText") return { value: null, matched: false };
        throw new Error(`STALE_REF: Browser ref belongs to another tab or snapshot: ${ref}. Take a new snapshot.`);
      }
      if (kind === "count") return { count: 1 };
      const element = asRecord(await this.callOnNode(target, stored.backendNodeId, LIVE_NODE_QUERY_FUNCTION));
      if (kind === "all") return { count: 1, elements: [element] };
      if (kind === "textContent") {
        const value = String(element.textContent ?? "");
        const maxLength = Math.max(1_000, Math.min(1_000_000, numberValue(payload.maxLength, 1_000_000)));
        return { value: truncate(value, maxLength), truncated: value.length > maxLength, matched: true };
      }
      if (kind === "innerText") {
        const value = String(element.innerText ?? element.textContent ?? "");
        const maxLength = Math.max(1_000, Math.min(1_000_000, numberValue(payload.maxLength, 1_000_000)));
        return { value: truncate(value, maxLength), truncated: value.length > maxLength, matched: true };
      }
      if (kind === "inputValue") return { value: element.value, matched: true };
      if (kind === "element") return { element, matched: true };
      if (kind === "checkValidity") return { valid: element.valid === true, validity: element.validity, matched: true };
      throw new Error(`Unsupported live DOM query kind: ${kind}`);
    }
    return await this.evaluate(target, liveQueryExpression(payload));
  }

  private async click(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const node = await this.resolveNode(task, target, payload);
    const before = await this.pageState(target);
    const clicked = await this.describeNode(target, node.backendNodeId);
    const point = await this.clickablePoint(target, node.backendNodeId);
    await this.assertHitTarget(target, node.backendNodeId);
    await this.requireConnection().send("Input.dispatchMouseEvent", { type: "mouseMoved", ...point }, target.sessionId);
    await this.requireConnection().send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, ...point }, target.sessionId);
    try {
      await this.requireConnection().send(
        "Input.dispatchMouseEvent",
        { type: "mouseReleased", button: "left", clickCount: 1, ...point },
        target.sessionId,
        1_500
      );
    } catch (error) {
      if (!task.pendingDialogs.has(target.targetId)) throw error;
    }
    if (!task.pendingDialogs.has(target.targetId)) {
      await this.waitForReady(target, numberValue(payload.timeoutMs, 8_000)).catch(() => undefined);
    }
    return {
      clicked,
      trusted: true,
      before,
      after: await this.pageStateOrDialog(task, target),
    };
  }

  private async hover(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const node = await this.resolveNode(task, target, payload);
    const point = await this.clickablePoint(target, node.backendNodeId);
    await this.assertHitTarget(target, node.backendNodeId);
    await this.requireConnection().send("Input.dispatchMouseEvent", { type: "mouseMoved", ...point }, target.sessionId);
    return { hovered: await this.describeNode(target, node.backendNodeId), trusted: true };
  }

  private async type(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const node = await this.resolveNode(task, target, payload);
    const inputText = stringValue(payload.inputText ?? payload.text);
    if (inputText === undefined) throw new Error("Missing required browser command field: inputText");
    const directFill = asRecord(await this.callOnNode(target, node.backendNodeId, `function(text, append) {
      const tag = this.tagName?.toLowerCase() || '';
      const type = String(this.type || '').toLowerCase();
      const directTypes = ['date', 'datetime-local', 'month', 'time', 'week', 'color', 'range'];
      if (tag !== 'input' || !directTypes.includes(type)) return { handled: false };
      const nextValue = append ? String(this.value || '') + String(text || '') : String(text || '');
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
      this.focus();
      if (setter) setter.call(this, nextValue);
      else this.value = nextValue;
      this.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: String(text || '') }));
      this.dispatchEvent(new Event('change', { bubbles: true }));
      return { handled: true, value: String(this.value || '') };
    }`, [inputText, Boolean(payload.append)]));
    if (directFill.handled) {
      const verification = await this.describeNode(target, node.backendNodeId);
      const verified = browserFilledValueMatches(verification, inputText, Boolean(payload.append));
      return { typed: verification, verified, trusted: false, directControlFill: true };
    }
    const point = await this.clickablePoint(target, node.backendNodeId);
    await this.assertHitTarget(target, node.backendNodeId);
    await this.requireConnection().send("Input.dispatchMouseEvent", { type: "mousePressed", button: "left", clickCount: 1, ...point }, target.sessionId);
    await this.requireConnection().send("Input.dispatchMouseEvent", { type: "mouseReleased", button: "left", clickCount: 1, ...point }, target.sessionId);
    if (!payload.append) {
      await this.callOnNode(target, node.backendNodeId, `function() {
        this.focus();
        if (typeof this.select === 'function') {
          this.select();
          return;
        }
        if (this.isContentEditable) {
          const selection = this.ownerDocument.getSelection();
          const range = this.ownerDocument.createRange();
          range.selectNodeContents(this);
          selection.removeAllRanges();
          selection.addRange(range);
        }
      }`);
    }
    if (inputText) await this.requireConnection().send("Input.insertText", { text: inputText }, target.sessionId);
    else if (!payload.append) await this.dispatchShortcut(target, "BACKSPACE");
    const verification = await this.describeNode(target, node.backendNodeId);
    return { typed: verification, verified: browserFilledValueMatches(verification, inputText, Boolean(payload.append)), trusted: true };
  }

  private async dropdownOptions(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const node = await this.resolveNode(task, target, payload);
    const result = await this.callOnNode(target, node.backendNodeId, `function() {
      if (!(this instanceof HTMLSelectElement)) throw new Error('Target is not a select menu');
      return Array.from(this.options).map((option, index) => ({ index, label: option.label, text: option.text, value: option.value, selected: option.selected, disabled: option.disabled }));
    }`);
    return { options: result };
  }

  private async select(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const node = await this.resolveNode(task, target, payload);
    const wanted = requireString(payload.value ?? payload.label, "value or label");
    const result = await this.callOnNode(target, node.backendNodeId, `function(wanted) {
      if (!(this instanceof HTMLSelectElement)) throw new Error('Target is not a select menu');
      const normalized = String(wanted).trim().toLocaleLowerCase();
      const option = Array.from(this.options).find((candidate) => candidate.value === wanted)
        || Array.from(this.options).find((candidate) => candidate.label.trim().toLocaleLowerCase() === normalized || candidate.text.trim().toLocaleLowerCase() === normalized);
      if (!option) return { ok: false, options: Array.from(this.options).map((candidate) => ({ label: candidate.label, value: candidate.value })) };
      this.value = option.value;
      this.dispatchEvent(new InputEvent('input', { bubbles: true }));
      this.dispatchEvent(new Event('change', { bubbles: true }));
      return { ok: this.value === option.value, label: option.label, value: this.value };
    }`, [wanted]);
    if (!asRecord(result).ok) {
      throw new Error(`No dropdown option matched "${wanted}". Available options: ${JSON.stringify(asRecord(result).options ?? [])}`);
    }
    return { selected: result, verified: true };
  }

  private async uploadFile(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const node = await this.resolveNode(task, target, payload);
    const files = await this.resolveUploadFiles(task, payload);
    await this.requireConnection().send("DOM.setFileInputFiles", {
      files,
      backendNodeId: node.backendNodeId,
    }, target.sessionId);
    const described = await this.describeNode(target, node.backendNodeId);
    return { uploaded: files.map((file) => basename(file)), target: described, verified: files.length > 0 };
  }

  private async resolveUploadFiles(task: PowerTask, payload: Record<string, unknown>) {
    const requested = Array.isArray(payload.paths)
      ? payload.paths.filter((value): value is string => typeof value === "string")
      : typeof payload.path === "string" ? [payload.path] : [];
    if (requested.length > 0) {
      const files: string[] = [];
      for (const value of requested) {
        const path = resolve(value);
        const info = await stat(path);
        if (!info.isFile()) throw new Error(`Upload path is not a file: ${path}`);
        if (info.size > 10 * 1024 * 1024) throw new Error(`Upload file is larger than 10 MB: ${basename(path)}`);
        files.push(path);
      }
      return files;
    }

    const directory = await mkdtemp(join(tmpdir(), "detach-browser-upload-"));
    const filename = safeFilename(stringValue(payload.fileName) || "detach-upload.txt");
    const path = join(directory, filename);
    const content = stringValue(payload.content) ?? "Created by Detach for this browser task.\n";
    await Bun.write(path, content);
    task.temporaryFiles.add(path);
    task.temporaryDirectories.add(directory);
    return [path];
  }

  private async key(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const shortcut = requireString(payload.key ?? payload.shortcut, "key");
    await this.dispatchShortcut(target, shortcut);
    await this.waitForReady(target, numberValue(payload.timeoutMs, 5_000)).catch(() => undefined);
    return { pressed: shortcut, trusted: true, page: await this.pageStateOrDialog(task, target) };
  }

  private async dispatchShortcut(target: TargetSession, shortcut: string) {
    const parsed = parseShortcut(shortcut);
    const base = {
      key: parsed.key,
      code: parsed.code,
      windowsVirtualKeyCode: parsed.keyCode,
      nativeVirtualKeyCode: parsed.keyCode,
      modifiers: parsed.modifiers,
    };
    await this.requireConnection().send("Input.dispatchKeyEvent", { type: "keyDown", ...base }, target.sessionId);
    await this.requireConnection().send("Input.dispatchKeyEvent", { type: "keyUp", ...base }, target.sessionId);
  }

  private async scroll(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    if (hasTarget(payload)) {
      const node = await this.resolveNode(task, target, payload);
      await this.requireConnection().send("DOM.scrollIntoViewIfNeeded", { backendNodeId: node.backendNodeId }, target.sessionId);
    } else {
      await this.evaluate(target, `window.scrollBy(${numberValue(payload.deltaX, 0)}, ${numberValue(payload.deltaY, Math.round(this.settings.viewportHeight * 0.75))}); ({scrollX, scrollY})`);
    }
    return await this.evaluate(target, "({ scrollX, scrollY })");
  }

  private async wait(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    if (Number.isFinite(Number(payload.delayMs))) {
      const delayMs = Math.max(0, Math.min(60_000, numberValue(payload.delayMs, 0)));
      await Bun.sleep(delayMs);
      return { matched: true, delayMs, ...(await this.pageStateOrDialog(task, target)) };
    }
    const timeoutMs = Math.max(100, Math.min(60_000, numberValue(payload.timeoutMs, 10_000)));
    const deadline = Date.now() + timeoutMs;
    const text = stringValue(payload.text);
    const selector = stringValue(payload.selector);
    const urlIncludes = stringValue(payload.urlIncludes);

    while (Date.now() < deadline) {
      const state = asRecord(await this.evaluate(target, `(() => {
        const selector = ${JSON.stringify(selector || "")};
        const text = ${JSON.stringify(text || "")};
        return {
          readyState: document.readyState,
          url: location.href,
          selectorFound: !selector || Boolean(document.querySelector(selector)),
          textFound: !text || (document.body?.innerText || '').includes(text)
        };
      })()`));
      if (
        state.readyState !== "loading"
        && state.selectorFound !== false
        && state.textFound !== false
        && (!urlIncludes || String(state.url).includes(urlIncludes))
      ) {
        return {
          matched: true,
          ...state,
          networkIdle: (this.inflightRequests.get(target.sessionId) ?? 0) === 0,
        };
      }
      await Bun.sleep(100);
    }
    throw new Error(`WAIT_TIMEOUT: Browser wait timed out after ${timeoutMs}ms`);
  }

  private async history(task: PowerTask, payload: Record<string, unknown>, direction: -1 | 1) {
    const target = await this.resolveTarget(task, payload);
    const history = await this.requireConnection().send("Page.getNavigationHistory", {}, target.sessionId);
    const index = Number(history.currentIndex) + direction;
    const entry = (history.entries as Array<Record<string, any>> | undefined)?.[index];
    if (!entry) throw new Error(direction < 0 ? "No previous page in browser history" : "No next page in browser history");
    await this.requireConnection().send("Page.navigateToHistoryEntry", { entryId: entry.id }, target.sessionId);
    await this.waitForReady(target, numberValue(payload.timeoutMs, 10_000));
    return await this.pageState(target);
  }

  private async refresh(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    await this.requireConnection().send("Page.reload", { ignoreCache: Boolean(payload.ignoreCache) }, target.sessionId);
    await this.waitForReady(target, numberValue(payload.timeoutMs, 10_000));
    return await this.pageState(target);
  }

  private async activateTab(task: PowerTask, payload: Record<string, unknown>) {
    const targetId = requireString(payload.tabId ?? payload.targetId, "tabId");
    if (!task.targets.has(targetId)) throw new Error(`Tab is outside this browser task: ${targetId}`);
    await this.requireConnection().send("Target.activateTarget", { targetId });
    task.activeTargetId = targetId;
    return await this.activeTab(task);
  }

  private async closeTab(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    if (task.targets.size <= 1) throw new Error("Cannot close the only tab in this browser task");
    await this.requireConnection().send("Target.closeTarget", { targetId: target.targetId });
    task.targets.delete(target.targetId);
    if (task.activeTargetId === target.targetId) task.activeTargetId = task.targets.keys().next().value!;
    return { closed: target.targetId, activeTab: await this.activeTab(task) };
  }

  private async screenshot(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    const format = payload.format === "jpeg" ? "jpeg" : "png";
    const result = await this.requireConnection().send("Page.captureScreenshot", {
      format,
      quality: format === "jpeg" ? Math.max(1, Math.min(100, numberValue(payload.quality, 80))) : undefined,
      fromSurface: true,
      captureBeyondViewport: Boolean(payload.fullPage),
      optimizeForSpeed: true,
    }, target.sessionId);
    const data = requireString(result.data, "screenshot data");
    return {
      tab: await this.activeTab(task),
      format,
      mimeType: `image/${format}`,
      data,
      dataUrl: `data:image/${format};base64,${data}`,
    };
  }

  private async resolveTarget(task: PowerTask, payload: Record<string, unknown>) {
    const targetId = stringValue(payload.tabId ?? payload.targetId) || task.activeTargetId;
    const existing = task.targets.get(targetId);
    if (existing) {
      task.activeTargetId = targetId;
      return existing;
    }
    throw new Error(`No browser tab found for this task: ${targetId}`);
  }

  private async resolveNode(task: PowerTask, target: TargetSession, payload: Record<string, unknown>) {
    const ref = stringValue(payload.ref);
    if (ref) {
      const stored = task.refs.get(ref);
      if (!stored || stored.targetId !== target.targetId) {
        throw new Error(`STALE_REF: Browser ref belongs to another tab or snapshot: ${ref}. Take a new snapshot.`);
      }
      return stored;
    }

    const selector = stringValue(payload.selector);
    const targetText = stringValue(payload.targetText ?? payload.text);
    if (!selector && !targetText) throw new Error("Browser command needs ref, selector, or targetText");
    const evaluated = await this.requireConnection().send("Runtime.evaluate", {
      expression: deepElementSearchExpression(selector, targetText),
      returnByValue: false,
      awaitPromise: true,
    }, target.sessionId);
    const objectId = evaluated.result?.objectId;
    if (!objectId) throw new Error(`No visible element found${selector ? ` for selector ${selector}` : ` for text ${targetText}`}`);
    const described = await this.requireConnection().send("DOM.describeNode", { objectId, depth: 0, pierce: true }, target.sessionId);
    const backendNodeId = Number(described.node?.backendNodeId);
    if (!backendNodeId) throw new Error("Could not resolve browser element");
    return { backendNodeId, targetId: target.targetId };
  }

  private async clickablePoint(target: TargetSession, backendNodeId: number) {
    await this.requireConnection().send("DOM.scrollIntoViewIfNeeded", { backendNodeId }, target.sessionId).catch(() => undefined);
    const result = await this.requireConnection().send("DOM.getContentQuads", { backendNodeId }, target.sessionId);
    const quad = (result.quads as number[][] | undefined)?.find((candidate) => candidate.length >= 8);
    if (!quad) throw new Error("Target has no clickable on-screen area");
    const x = (quad[0]! + quad[2]! + quad[4]! + quad[6]!) / 4;
    const y = (quad[1]! + quad[3]! + quad[5]! + quad[7]!) / 4;
    return { x, y };
  }

  private async assertHitTarget(target: TargetSession, backendNodeId: number) {
    const hit = asRecord(await this.callOnNode(target, backendNodeId, `function() {
      const rect = this.getBoundingClientRect();
      const x = Math.min(innerWidth - 1, Math.max(0, rect.left + rect.width / 2));
      const y = Math.min(innerHeight - 1, Math.max(0, rect.top + rect.height / 2));
      const top = this.ownerDocument.elementFromPoint(x, y);
      return {
        ok: !top || top === this || this.contains(top),
        coveredBy: top && top !== this ? (top.getAttribute?.('aria-label') || top.innerText || top.tagName || '') : ''
      };
    }`));
    if (!hit.ok) throw new Error(`Target is covered by ${truncate(String(hit.coveredBy || "another element"), 120)}. Take a new snapshot or scroll before acting.`);
  }

  private async describeNode(target: TargetSession, backendNodeId: number) {
    return asRecord(await this.callOnNode(target, backendNodeId, `function() {
      const isPassword = this instanceof HTMLInputElement && this.type.toLowerCase() === 'password';
      return {
        tag: this.tagName?.toLowerCase() || '',
        type: String(this.type || ''),
        role: this.getAttribute?.('role') || '',
        name: this.getAttribute?.('aria-label') || this.innerText || this.textContent || '',
        value: isPassword ? '[password]' : ('value' in this ? String(this.value || '') : ''),
        checked: 'checked' in this ? Boolean(this.checked) : undefined,
        valid: this.validity ? Boolean(this.validity.valid) : true,
        disabled: Boolean(this.disabled || this.getAttribute?.('aria-disabled') === 'true'),
        connected: Boolean(this.isConnected)
      };
    }`));
  }

  private async callOnNode(target: TargetSession, backendNodeId: number, functionDeclaration: string, arguments_: unknown[] = []) {
    const resolved = await this.requireConnection().send("DOM.resolveNode", { backendNodeId }, target.sessionId);
    const objectId = resolved.object?.objectId;
    if (!objectId) throw new Error("Browser element is no longer attached to the page. Take a new snapshot.");
    const result = await this.requireConnection().send("Runtime.callFunctionOn", {
      objectId,
      functionDeclaration,
      arguments: arguments_.map((value) => ({ value })),
      returnByValue: true,
      awaitPromise: true,
    }, target.sessionId);
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || "Browser element operation failed");
    return result.result?.value;
  }

  private async evaluate(target: TargetSession, expression: string) {
    const result = await this.requireConnection().send("Runtime.evaluate", {
      expression,
      returnByValue: true,
      awaitPromise: true,
    }, target.sessionId);
    if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || "Browser evaluation failed");
    return result.result?.value;
  }

  private async evaluateValue(task: PowerTask, payload: Record<string, unknown>, expression: string) {
    const target = await this.resolveTarget(task, payload);
    const value = await this.evaluate(target, expression);
    return { value, text: typeof value === "string" ? value : undefined };
  }

  private async pageState(target: TargetSession) {
    return asRecord(await this.evaluate(target, "({ url: location.href, title: document.title, readyState: document.readyState })"));
  }

  private async pageStateOrDialog(task: PowerTask, target: TargetSession) {
    if (task.pendingDialogs.has(target.targetId)) return { dialogOpen: true };
    try {
      return await this.pageState(target);
    } catch (error) {
      if (task.pendingDialogs.has(target.targetId)) return { dialogOpen: true };
      throw error;
    }
  }

  private async waitForReady(target: TargetSession, timeoutMs: number) {
    const deadline = Date.now() + Math.max(500, Math.min(timeoutMs, 60_000));
    let stableSamples = 0;
    let previousSignature = "";
    let usableSince = 0;
    let lastState: Record<string, any> = {};
    while (Date.now() < deadline) {
      const state = asRecord(await this.evaluate(target, "({ readyState: document.readyState, url: location.href, signature: `${document.body?.childElementCount || 0}:${document.body?.innerText?.length || 0}` })").catch(() => ({})));
      lastState = state;
      const networkIdle = (this.inflightRequests.get(target.sessionId) ?? 0) === 0
        && Date.now() - (this.lastNetworkActivity.get(target.sessionId) ?? 0) >= 250;
      const signature = String(state.signature || "");
      stableSamples = signature && signature === previousSignature ? stableSamples + 1 : 0;
      previousSignature = signature;
      const usable = state.readyState !== "loading" && Boolean(signature) && stableSamples >= 1;
      if (usable && networkIdle) return { ...state, networkIdle: true, softReady: false };
      if (usable) {
        usableSince ||= Date.now();
        if (Date.now() - usableSince >= 750) return { ...state, networkIdle: false, softReady: true };
      } else {
        usableSince = 0;
      }
      await Bun.sleep(100);
    }
    if (lastState.readyState !== "loading" && lastState.url) {
      return { ...lastState, networkIdle: false, softReady: true, timedOut: true };
    }
    throw new Error(`Page did not become ready within ${timeoutMs}ms`);
  }

  private readEvents(task: PowerTask, drain: boolean) {
    const events = task.events.map((event) => ({ ...event }));
    if (drain) task.events.length = 0;
    return { events };
  }

  private async handleDialog(task: PowerTask, payload: Record<string, unknown>) {
    const target = await this.resolveTarget(task, payload);
    if (!task.pendingDialogs.has(target.targetId)) throw new Error("No JavaScript dialog is open in the active tab");
    const action = payload.action === "dismiss" ? "dismiss" : "accept";
    await this.requireConnection().send("Page.handleJavaScriptDialog", {
      accept: action === "accept",
      ...(typeof payload.promptText === "string" ? { promptText: payload.promptText } : {}),
    }, target.sessionId);
    task.pendingDialogs.delete(target.targetId);
    return { handled: true, action, tabId: target.targetId };
  }

  private taskForSession(sessionId?: string) {
    if (!sessionId) return undefined;
    for (const task of this.tasks.values()) {
      for (const target of task.targets.values()) {
        if (target.sessionId === sessionId) return { task, target };
      }
    }
    return undefined;
  }

  private pushEvent(task: PowerTask, event: Omit<BrowserEvent, "timestamp"> & { type: BrowserEvent["type"] }) {
    const queued: BrowserEvent = { ...event, timestamp: Date.now() };
    const previous = task.events.at(-1);
    const duplicateNavigation = queued.type === "navigation"
      && previous?.type === "navigation"
      && previous.tabId === queued.tabId
      && previous.url === queued.url;
    const replaceDownloadProgress = queued.type === "download"
      && queued.phase === "inProgress"
      && previous?.type === "download"
      && previous.phase === "inProgress"
      && previous.guid === queued.guid;
    if (replaceDownloadProgress) task.events[task.events.length - 1] = queued;
    else if (!duplicateNavigation) task.events.push(queued);
    if (task.events.length > 100) task.events.splice(0, task.events.length - 100);
  }

  private requireConnection() {
    if (!this.connection) throw new Error("Power browser is not connected");
    return this.connection;
  }
}

export function parseSemanticElements(
  snapshot: Record<string, any>,
  axTree: Record<string, any>,
  targetId: string,
  maxElements = 180
) {
  const strings = (snapshot.strings ?? []) as string[];
  const axByBackend = new Map<number, Record<string, any>>();
  const parentByBackend = new Map<number, number | undefined>();
  for (const node of (axTree.nodes ?? []) as Array<Record<string, any>>) {
    if (typeof node.backendDOMNodeId === "number") axByBackend.set(node.backendDOMNodeId, node);
  }

  const results: Array<Record<string, any>> = [];
  for (const document of (snapshot.documents ?? []) as Array<Record<string, any>>) {
    const nodes = document.nodes ?? {};
    const layout = document.layout ?? {};
    const boundsByNode = new Map<number, number[]>();
    for (let i = 0; i < (layout.nodeIndex ?? []).length; i += 1) {
      boundsByNode.set(layout.nodeIndex[i], layout.bounds?.[i] ?? []);
    }
    const clickable = new Set<number>(nodes.isClickable?.index ?? []);

    for (let index = 0; index < (nodes.backendNodeId ?? []).length; index += 1) {
      const backendNodeId = Number(nodes.backendNodeId[index]);
      const parentIndex = Number(nodes.parentIndex?.[index] ?? -1);
      const parentBackend = parentIndex >= 0 ? Number(nodes.backendNodeId?.[parentIndex]) : undefined;
      if (backendNodeId) parentByBackend.set(backendNodeId, parentBackend || undefined);
      if (!backendNodeId || !boundsByNode.has(index)) continue;
      const tag = stringAt(strings, nodes.nodeName?.[index]).toLowerCase();
      const attributes = parseAttributes(strings, nodes.attributes?.[index]);
      const ax = axByBackend.get(backendNodeId);
      const role = String(ax?.role?.value || attributes.role || implicitRole(tag, attributes));
      const name = normalizeWhitespace(String(ax?.name?.value || attributes["aria-label"] || attributes.placeholder || attributes.alt || ""));
      const value = isPassword(tag, attributes)
        ? "[password]"
        : normalizeWhitespace(String(ax?.value?.value || sparseString(nodes.inputValue, index, strings) || attributes.value || ""));
      const interactive = clickable.has(index) || isInteractive(tag, role, attributes);
      if (!interactive && !isMeaningfulSemanticNode(tag, role, name, value)) continue;
      const bounds = boundsByNode.get(index) ?? [];
      const ref = `cdp-${targetId.slice(-6)}-${backendNodeId}`;
      results.push({
        ref,
        backendNodeId,
        parentBackend,
        depth: nodeDepth(nodes.parentIndex ?? [], index),
        tag,
        role,
        name: truncate(name, 240),
        htmlName: attributes.name || "",
        id: attributes.id || "",
        text: truncate(name, 240),
        value: truncate(value, 240),
        type: attributes.type || "",
        placeholder: attributes.placeholder || "",
        href: attributes.href || "",
        disabled: Boolean(axProperty(ax, "disabled") || attributes.disabled !== undefined || attributes["aria-disabled"] === "true"),
        checked: axProperty(ax, "checked"),
        selected: axProperty(ax, "selected"),
        expanded: axProperty(ax, "expanded"),
        required: axProperty(ax, "required"),
        interactive,
        frameId: document.frameId,
        shadowRoot: sparseString(nodes.shadowRootType, index, strings) || undefined,
        rect: {
          x: Math.round(Number(bounds[0] ?? 0)),
          y: Math.round(Number(bounds[1] ?? 0)),
          width: Math.round(Number(bounds[2] ?? 0)),
          height: Math.round(Number(bounds[3] ?? 0)),
        },
      });
      if (results.length >= maxElements) return finalizeSemanticHierarchy(results, parentByBackend, targetId);
    }
  }
  return finalizeSemanticHierarchy(results, parentByBackend, targetId);
}

function finalizeSemanticHierarchy(results: Array<Record<string, any>>, parentByBackend: Map<number, number | undefined>, targetId: string) {
  const interactiveBackends = new Set(results.map((result) => Number(result.backendNodeId)));
  for (const result of results) {
    let parent = Number(result.parentBackend || 0) || undefined;
    const seen = new Set<number>();
    while (parent && !interactiveBackends.has(parent) && !seen.has(parent)) {
      seen.add(parent);
      parent = parentByBackend.get(parent);
    }
    result.parentRef = parent ? `cdp-${targetId.slice(-6)}-${parent}` : undefined;
    delete result.parentBackend;
  }
  return results;
}

const LIVE_NODE_QUERY_FUNCTION = `function() {
  const tagName = this.tagName?.toLowerCase() || '';
  const type = String(this.type || '').toLowerCase();
  const isPassword = tagName === 'input' && type === 'password';
  const value = isPassword
    ? '[password]'
    : tagName === 'input' && type === 'file'
      ? Array.from(this.files || []).map((file) => file.name).join(', ')
      : 'value' in this ? String(this.value ?? '') : this.isContentEditable ? String(this.textContent ?? '') : undefined;
  const validity = this.validity ? {
    valid: Boolean(this.validity.valid),
    valueMissing: Boolean(this.validity.valueMissing),
    typeMismatch: Boolean(this.validity.typeMismatch),
    patternMismatch: Boolean(this.validity.patternMismatch),
    tooLong: Boolean(this.validity.tooLong),
    tooShort: Boolean(this.validity.tooShort),
    rangeUnderflow: Boolean(this.validity.rangeUnderflow),
    rangeOverflow: Boolean(this.validity.rangeOverflow),
    stepMismatch: Boolean(this.validity.stepMismatch),
    badInput: Boolean(this.validity.badInput),
    customError: Boolean(this.validity.customError)
  } : { valid: true };
  return {
    tagName,
    textContent: String(this.textContent ?? ''),
    innerText: String(this.innerText ?? this.textContent ?? ''),
    value,
    href: this.href || this.getAttribute?.('href') || '',
    id: this.id || '',
    name: String(this.name || ''),
    type: String(this.type || ''),
    accept: String(this.accept || ''),
    placeholder: String(this.placeholder || ''),
    checked: Boolean(this.checked),
    selected: Boolean(this.selected),
    disabled: Boolean(this.disabled || this.getAttribute?.('aria-disabled') === 'true'),
    required: Boolean(this.required || this.hasAttribute?.('required')),
    multiple: Boolean(this.multiple),
    files: tagName === 'input' && type === 'file'
      ? Array.from(this.files || []).slice(0, 100).map((file) => ({ name: file.name, type: file.type, size: file.size }))
      : [],
    options: tagName === 'select'
      ? Array.from(this.options || []).slice(0, 500).map((option, index) => ({
          index, label: option.label, text: option.text, textContent: option.textContent || option.text,
          value: option.value, selected: option.selected, disabled: option.disabled
        }))
      : [],
    valid: typeof this.checkValidity === 'function' ? this.checkValidity() : true,
    validity,
    attributes: Object.fromEntries(Array.from(this.attributes || [])
      .filter((attribute) => attribute.name !== 'value' && attribute.name !== 'data-lazzy-ref')
      .slice(0, 40)
      .map((attribute) => [attribute.name, String(attribute.value).slice(0, 1000)]))
  };
}`;

function liveQueryExpression(payload: Record<string, unknown>) {
  const query = {
    kind: stringValue(payload.kind) || "all",
    selector: stringValue(payload.selector) || "",
    targetText: stringValue(payload.targetText) || "",
    role: stringValue(payload.role) || "",
    name: stringValue(payload.name) || "",
    label: stringValue(payload.label) || "",
    exact: Boolean(payload.exact),
    maxLength: Math.max(1_000, Math.min(1_000_000, numberValue(payload.maxLength, 1_000_000))),
    maxResults: Math.max(1, Math.min(1_000, numberValue(payload.maxResults, 250))),
  };
  return `(() => {
    const query = ${JSON.stringify(query)};
    const normalize = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
    const roots = [];
    const visit = (root) => {
      if (!root || roots.includes(root)) return;
      roots.push(root);
      for (const element of root.querySelectorAll?.('*') || []) {
        if (element.shadowRoot) visit(element.shadowRoot);
        if (element instanceof HTMLIFrameElement) {
          try { if (element.contentDocument) visit(element.contentDocument); } catch {}
        }
      }
    };
    visit(document);
    const unique = (values) => Array.from(new Set(values)).filter((element) => element?.nodeType === 1);
    const implicitRole = (element) => {
      const tag = element.tagName?.toLowerCase();
      if (tag === 'a' && element.getAttribute('href')) return 'link';
      if (tag === 'button') return 'button';
      if (tag === 'select') return 'combobox';
      if (tag === 'textarea') return 'textbox';
      if (tag === 'input') {
        const type = String(element.type || 'text').toLowerCase();
        if (['button', 'submit', 'reset'].includes(type)) return 'button';
        if (type === 'checkbox') return 'checkbox';
        if (type === 'radio') return 'radio';
        return 'textbox';
      }
      return '';
    };
    const accessibleName = (element) => {
      const labelledBy = element.getAttribute?.('aria-labelledby');
      const labelledText = labelledBy
        ? labelledBy.split(/\\s+/).map((id) => element.ownerDocument.getElementById(id)?.textContent || '').join(' ')
        : '';
      const labelText = 'labels' in element && element.labels
        ? Array.from(element.labels).map((item) => item.textContent || '').join(' ')
        : '';
      return normalize(element.getAttribute?.('aria-label') || labelledText || labelText
        || element.getAttribute?.('alt') || element.getAttribute?.('placeholder')
        || element.innerText || element.textContent || '');
    };
    let elements = [];
    if (query.selector) {
      for (const root of roots) elements.push(...root.querySelectorAll(query.selector));
      elements = unique(elements);
    } else {
      const role = normalize(query.role).toLocaleLowerCase();
      const name = normalize(query.name).toLocaleLowerCase();
      const label = normalize(query.label).toLocaleLowerCase();
      const targetText = normalize(query.targetText).toLocaleLowerCase();
      elements = unique(roots.flatMap((root) => Array.from(root.querySelectorAll?.('*') || []))).filter((element) => {
        if (role && normalize(element.getAttribute?.('role') || implicitRole(element)).toLocaleLowerCase() !== role) return false;
        const candidateName = accessibleName(element).toLocaleLowerCase();
        if (name && !(query.exact ? candidateName === name : candidateName.includes(name))) return false;
        if (label && !(query.exact ? candidateName === label : candidateName.includes(label))) return false;
        if (targetText) {
          const text = normalize(element.innerText || element.textContent || element.getAttribute?.('aria-label') || '').toLocaleLowerCase();
          if (!(query.exact ? text === targetText : text.includes(targetText))) return false;
        }
        return Boolean(role || name || label || targetText);
      });
    }
    const serialize = (element) => {
      const tagName = element.tagName?.toLowerCase() || '';
      const type = String(element.type || '').toLowerCase();
      const isPassword = tagName === 'input' && type === 'password';
      const validity = element.validity ? {
        valid: Boolean(element.validity.valid),
        valueMissing: Boolean(element.validity.valueMissing),
        typeMismatch: Boolean(element.validity.typeMismatch),
        patternMismatch: Boolean(element.validity.patternMismatch),
        tooLong: Boolean(element.validity.tooLong),
        tooShort: Boolean(element.validity.tooShort),
        rangeUnderflow: Boolean(element.validity.rangeUnderflow),
        rangeOverflow: Boolean(element.validity.rangeOverflow),
        stepMismatch: Boolean(element.validity.stepMismatch),
        badInput: Boolean(element.validity.badInput),
        customError: Boolean(element.validity.customError)
      } : { valid: true };
      return {
        tagName,
        textContent: String(element.textContent ?? '').slice(0, 20000),
        innerText: String(element.innerText ?? element.textContent ?? '').slice(0, 20000),
        value: isPassword ? '[password]'
          : tagName === 'input' && type === 'file'
            ? Array.from(element.files || []).map((file) => file.name).join(', ')
            : 'value' in element ? String(element.value ?? '') : element.isContentEditable ? String(element.textContent ?? '') : undefined,
        href: element.href || element.getAttribute?.('href') || '',
        id: element.id || '',
        name: String(element.name || ''),
        type: String(element.type || ''),
        accept: String(element.accept || ''),
        placeholder: String(element.placeholder || ''),
        checked: Boolean(element.checked),
        selected: Boolean(element.selected),
        disabled: Boolean(element.disabled || element.getAttribute?.('aria-disabled') === 'true'),
        required: Boolean(element.required || element.hasAttribute?.('required')),
        multiple: Boolean(element.multiple),
        files: tagName === 'input' && type === 'file'
          ? Array.from(element.files || []).slice(0, 100).map((file) => ({ name: file.name, type: file.type, size: file.size }))
          : [],
        options: tagName === 'select'
          ? Array.from(element.options || []).slice(0, 500).map((option, index) => ({
              index, label: option.label, text: option.text, textContent: option.textContent || option.text,
              value: option.value, selected: option.selected, disabled: option.disabled
            }))
          : [],
        valid: typeof element.checkValidity === 'function' ? element.checkValidity() : true,
        validity,
        attributes: Object.fromEntries(Array.from(element.attributes || [])
          .filter((attribute) => attribute.name !== 'value' && attribute.name !== 'data-lazzy-ref')
          .slice(0, 40)
          .map((attribute) => [attribute.name, String(attribute.value).slice(0, 1000)]))
      };
    };
    if (query.kind === 'count') return { count: elements.length };
    if (query.kind === 'all') return { count: elements.length, elements: elements.slice(0, query.maxResults).map(serialize) };
    const element = elements[0];
    if (!element) {
      if (query.kind === 'textContent' || query.kind === 'innerText') return { value: null, matched: false };
      throw new Error('No page element matched the live ' + query.kind + ' query');
    }
    if (query.kind === 'textContent') {
      const value = String(element.textContent ?? '');
      return { value: value.slice(0, query.maxLength), truncated: value.length > query.maxLength, matched: true };
    }
    if (query.kind === 'innerText') {
      const value = String(element.innerText ?? element.textContent ?? '');
      return { value: value.slice(0, query.maxLength), truncated: value.length > query.maxLength, matched: true };
    }
    if (query.kind === 'inputValue') {
      const result = serialize(element);
      if (result.value === undefined) throw new Error('Matched page element does not expose an input value');
      return { value: result.value, matched: true };
    }
    if (query.kind === 'element') return { element: serialize(element), matched: true };
    if (query.kind === 'checkValidity') {
      const result = serialize(element);
      return { valid: result.valid === true, validity: result.validity, matched: true };
    }
    throw new Error('Unsupported live DOM query kind: ' + query.kind);
  })()`;
}

const SNAPSHOT_PAGE_SCRIPT = `(() => {
  const normalize = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
  const roots = [];
  const visit = (root) => {
    if (!root || roots.includes(root)) return;
    roots.push(root);
    for (const element of root.querySelectorAll?.('*') || []) {
      if (element.shadowRoot) visit(element.shadowRoot);
      if (element instanceof HTMLIFrameElement) {
        try { if (element.contentDocument) visit(element.contentDocument); } catch {}
      }
    }
  };
  visit(document);
  const text = roots.map((root) => root.body?.innerText || root.textContent || '').map(normalize).filter(Boolean).join(' ');
  const headings = roots.flatMap((root) => Array.from(root.querySelectorAll?.('h1,h2,h3,[role="heading"]') || []).slice(0, 30).map((node) => ({
    level: node.tagName?.toLowerCase() || 'heading',
    text: normalize(node.innerText || node.textContent || '')
  })));
  const tables = roots.flatMap((root) => Array.from(root.querySelectorAll?.('table') || []).slice(0, 12).map((table) => ({
    caption: normalize(table.caption?.innerText || ''),
    rows: Array.from(table.rows || []).slice(0, 40).map((row) => Array.from(row.cells || []).slice(0, 20).map((cell) => normalize(cell.innerText || cell.textContent || '')))
  })));
  return {
    url: location.href,
    title: document.title,
    readyState: document.readyState,
    viewport: { width: innerWidth, height: innerHeight, scrollX, scrollY, devicePixelRatio },
    meta: { description: document.querySelector('meta[name="description"]')?.content || '', language: document.documentElement.lang || '', headings },
    text,
    tables
  };
})()`;

function deepElementSearchExpression(selector?: string, targetText?: string) {
  return `(() => {
    const selector = ${JSON.stringify(selector || "")};
    const needle = ${JSON.stringify(normalizeWhitespace(targetText || "").toLocaleLowerCase())};
    const seen = new Set();
    const roots = [document];
    while (roots.length) {
      const root = roots.shift();
      if (!root || seen.has(root)) continue;
      seen.add(root);
      if (selector) { try { const match = root.querySelector(selector); if (match) return match; } catch {} }
      for (const element of root.querySelectorAll?.('*') || []) {
        if (element.shadowRoot) roots.push(element.shadowRoot);
        if (element instanceof HTMLIFrameElement) { try { if (element.contentDocument) roots.push(element.contentDocument); } catch {} }
        if (needle) {
          const text = String(element.getAttribute?.('aria-label') || element.innerText || element.textContent || '').replace(/\\s+/g, ' ').trim().toLocaleLowerCase();
          const rect = element.getBoundingClientRect?.();
          if (text.includes(needle) && rect?.width > 0 && rect?.height > 0) return element;
        }
      }
    }
    return null;
  })()`;
}

async function findChromiumExecutable() {
  const configured = Bun.env.DETACH_POWER_BROWSER_EXECUTABLE?.trim();
  const candidates = [
    configured,
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
  ].filter((value): value is string => Boolean(value));
  for (const candidate of candidates) {
    try {
      if ((await stat(candidate)).isFile()) return candidate;
    } catch {
      // Try the next installed browser.
    }
  }
  return undefined;
}

async function connectCDPWithRetry(url: string, timeoutMs = 10_000) {
  const deadline = Date.now() + timeoutMs;
  let lastError: unknown;
  while (Date.now() < deadline) {
    try {
      return await CDPConnection.connect(url, Math.min(2_000, Math.max(250, deadline - Date.now())));
    } catch (error) {
      lastError = error;
      await Bun.sleep(100);
    }
  }
  throw new Error(`Could not connect to the Power browser after ${timeoutMs}ms: ${lastError instanceof Error ? lastError.message : String(lastError)}`);
}

function defaultPowerProfileDirectory() {
  return join(homedir(), "Library", "Application Support", "Detach", "PowerBrowser");
}

function parseAttributes(strings: string[], encoded?: number[]) {
  const attributes: Record<string, string> = {};
  for (let index = 0; index < (encoded?.length ?? 0); index += 2) {
    attributes[stringAt(strings, encoded?.[index])] = stringAt(strings, encoded?.[index + 1]);
  }
  return attributes;
}

function sparseString(data: Record<string, any> | undefined, nodeIndex: number, strings: string[]) {
  const sparseIndex = data?.index?.indexOf(nodeIndex) ?? -1;
  return sparseIndex >= 0 ? stringAt(strings, data?.value?.[sparseIndex]) : "";
}

function stringAt(strings: string[], index: unknown) {
  return typeof index === "number" && index >= 0 ? strings[index] ?? "" : "";
}

function axProperty(node: Record<string, any> | undefined, name: string) {
  return node?.properties?.find((property: Record<string, any>) => property.name === name)?.value?.value;
}

function isInteractive(tag: string, role: string, attributes: Record<string, string>) {
  if (["a", "button", "input", "textarea", "select", "summary", "option"].includes(tag)) return true;
  if (attributes.contenteditable === "true" || (attributes.tabindex && attributes.tabindex !== "-1")) return true;
  return ["button", "link", "textbox", "combobox", "checkbox", "radio", "menuitem", "option", "switch", "slider", "tab"].includes(role.toLowerCase());
}

function isMeaningfulSemanticNode(tag: string, role: string, name: string, value: string) {
  if (!name && !value) return false;
  const normalizedRole = role.toLowerCase();
  if ([
    "heading", "statictext", "paragraph", "list", "listitem", "table", "row", "cell", "gridcell",
    "columnheader", "rowheader", "navigation", "main", "form", "region", "dialog", "alert", "status",
    "article", "figure", "img", "term", "definition",
  ].includes(normalizedRole)) return true;
  return ["h1", "h2", "h3", "h4", "h5", "h6", "p", "li", "td", "th", "caption"].includes(tag);
}

function implicitRole(tag: string, attributes: Record<string, string>) {
  if (tag === "a" && attributes.href) return "link";
  if (tag === "button") return "button";
  if (tag === "select") return "combobox";
  if (tag === "textarea") return "textbox";
  if (tag === "input") {
    const type = (attributes.type || "text").toLowerCase();
    if (["button", "submit", "reset"].includes(type)) return "button";
    if (type === "checkbox") return "checkbox";
    if (type === "radio") return "radio";
    return "textbox";
  }
  return "";
}

function isPassword(tag: string, attributes: Record<string, string>) {
  return tag === "input" && (attributes.type || "").toLowerCase() === "password";
}

function nodeDepth(parents: number[], index: number) {
  let depth = 0;
  let current = parents[index] ?? -1;
  const seen = new Set<number>();
  while (current >= 0 && !seen.has(current) && depth < 50) {
    seen.add(current);
    depth += 1;
    current = parents[current] ?? -1;
  }
  return depth;
}

function parseShortcut(shortcut: string) {
  const pieces = shortcut.toUpperCase().replace(/CMD|COMMAND/g, "META").replace(/OPTION/g, "ALT").split("+").map((part) => part.trim()).filter(Boolean);
  let modifiers = 0;
  if (pieces.includes("ALT")) modifiers |= 1;
  if (pieces.includes("CTRL") || pieces.includes("CONTROL")) modifiers |= 2;
  if (pieces.includes("META")) modifiers |= 4;
  if (pieces.includes("SHIFT")) modifiers |= 8;
  const rawKey = pieces.find((part) => !["ALT", "CTRL", "CONTROL", "META", "SHIFT"].includes(part)) || "ENTER";
  const keys: Record<string, [string, string, number]> = {
    ENTER: ["Enter", "Enter", 13], TAB: ["Tab", "Tab", 9], ESC: ["Escape", "Escape", 27], ESCAPE: ["Escape", "Escape", 27],
    BACKSPACE: ["Backspace", "Backspace", 8], DELETE: ["Delete", "Delete", 46], SPACE: [" ", "Space", 32],
    ARROWUP: ["ArrowUp", "ArrowUp", 38], ARROWDOWN: ["ArrowDown", "ArrowDown", 40], ARROWLEFT: ["ArrowLeft", "ArrowLeft", 37], ARROWRIGHT: ["ArrowRight", "ArrowRight", 39],
    HOME: ["Home", "Home", 36], END: ["End", "End", 35], PAGEUP: ["PageUp", "PageUp", 33], PAGEDOWN: ["PageDown", "PageDown", 34],
  };
  const mapped = keys[rawKey] ?? [rawKey.length === 1 ? rawKey.toLowerCase() : rawKey, rawKey.length === 1 ? `Key${rawKey}` : rawKey, rawKey.length === 1 ? rawKey.charCodeAt(0) : 0];
  return { key: mapped[0], code: mapped[1], keyCode: mapped[2], modifiers };
}

function hasTarget(payload: Record<string, unknown>) {
  return Boolean(payload.ref || payload.selector || payload.targetText);
}

function requireWebUrl(value: unknown) {
  const url = requireString(value, "url");
  if (!/^https?:\/\//i.test(url) && url !== "about:blank") throw new Error("Browser URLs must start with http:// or https://");
  return url;
}

function requireString(value: unknown, name: string) {
  if (typeof value !== "string" || !value.trim()) throw new Error(`Missing required ${name}`);
  return value.trim();
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function numberValue(value: unknown, fallback: number) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function normalizeWhitespace(value: string) {
  return value.replace(/\s+/g, " ").trim();
}

function browserFilledValueMatches(element: Record<string, any>, expected: string, append: boolean) {
  const actual = String(element.value ?? "");
  if (append ? actual.endsWith(expected) : actual === expected) return true;
  if (append || String(element.type || "").toLowerCase() !== "email" || element.valid !== true) return false;
  const at = expected.lastIndexOf("@");
  if (at <= 0 || at === expected.length - 1) return false;
  try {
    const normalizedDomain = new URL(`http://${expected.slice(at + 1)}`).hostname;
    return actual === `${expected.slice(0, at)}@${normalizedDomain}`;
  } catch {
    return false;
  }
}

function truncate(value: string, maxLength: number) {
  return value.length <= maxLength ? value : `${value.slice(0, maxLength)}...`;
}

function safeFilename(value: string) {
  const cleaned = Array.from(value.normalize("NFC")
    .replace(/[\\/:\u0000-\u001F\u007F]/g, "_")
    .replace(/^\.+/, "")
    .trim()).slice(0, 180).join("");
  return cleaned && cleaned !== "." && cleaned !== ".." ? cleaned : "detach-upload.txt";
}

function asRecord(value: unknown): Record<string, any> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  return value as Record<string, any>;
}
