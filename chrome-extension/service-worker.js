const NATIVE_HOST = "com.lazzy.browser";
const DEFAULT_RUNTIME_CONFIG = { port: 3847, token: "detach-development" };
const CONTENT_TARGET = "lazzy-content";
const COMMAND_TIMEOUT_MS = 20_000;
const MAX_RECONNECT_DELAY_MS = 30_000;
const HEARTBEAT_INTERVAL_MS = 20_000;

let nativePort;
const sensitiveTabIds = new Set();
let nativeConnected = false;
let runtimeConnected = false;
let nativeReconnectTimer;
let nativeReconnectAttempt = 0;
let runtimeSocket;
let runtimeReconnectTimer;
let runtimeReconnectAttempt = 0;
let runtimeHeartbeat;
let nativeFallbackTimer;
let lastNativeError;
const pendingCommands = new Map();
const taskWindows = new Map();
const taskEvents = new Map();
const downloadTasks = new Map();
const downloadMetadata = new Map();
const refTargets = new Map();
const navigationRevisions = new Map();
const activeFrameByTab = new Map();
let recentInteraction;
let creatingOffscreenDocument;

chrome.runtime.onInstalled.addListener(() => {
  chrome.storage.local.set({
    lazzyBrowserAgent: {
      nativeHost: NATIVE_HOST,
      installedAt: Date.now()
    }
  });
});

chrome.runtime.onStartup.addListener(connectBridge);

chrome.tabs.onCreated.addListener((tab) => {
  const runId = runIdForWindow(tab.windowId);
  if (runId) {
    queueTabCreated(runId, tab);
    return;
  }
  if (Number.isInteger(tab.openerTabId)) {
    tabsGet(tab.openerTabId).then((opener) => {
      const openerRunId = runIdForWindow(opener.windowId);
      if (openerRunId) queueTabCreated(openerRunId, tab);
    }).catch(() => undefined);
  }
});

function queueTabCreated(runId, tab) {
  queueTaskEvent(runId, {
    type: Number.isInteger(tab.openerTabId) ? "popup" : "new_tab",
    tabId: tab.id,
    openerTabId: tab.openerTabId,
    url: tab.url || tab.pendingUrl || "",
    title: tab.title || ""
  });
}

chrome.tabs.onRemoved.addListener((tabId, removeInfo) => {
  sensitiveTabIds.delete(tabId);
  clearTabRefs(tabId);
  navigationRevisions.delete(tabId);
  const runId = runIdForWindow(removeInfo.windowId);
  if (runId) queueTaskEvent(runId, { type: "tab_closed", tabId });
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.url) {
    sensitiveTabIds.delete(tabId);
    clearTabRefs(tabId);
  }
  const runId = runIdForWindow(tab.windowId);
  if (!runId || (!changeInfo.url && changeInfo.status !== "complete")) return;
  queueTaskEvent(runId, {
    type: "navigation",
    tabId,
    url: changeInfo.url || tab.url || "",
    status: changeInfo.status || tab.status || "unknown"
  });
});

for (const [event, phase] of [
  [chrome.webNavigation.onBeforeNavigate, "before"],
  [chrome.webNavigation.onCommitted, "committed"],
  [chrome.webNavigation.onDOMContentLoaded, "dom_content_loaded"],
  [chrome.webNavigation.onCompleted, "completed"],
  [chrome.webNavigation.onHistoryStateUpdated, "history"],
  [chrome.webNavigation.onReferenceFragmentUpdated, "fragment"],
]) {
  event.addListener((details) => recordNavigation(details, phase));
}

chrome.webNavigation.onErrorOccurred.addListener((details) => {
  recordNavigation(details, "error");
  tabsGet(details.tabId).then((tab) => {
    const runId = runIdForWindow(tab.windowId);
    if (runId) queueTaskEvent(runId, {
      type: "failure",
      failureType: "navigation",
      tabId: details.tabId,
      frameId: details.frameId,
      documentId: details.documentId,
      url: details.url,
      error: details.error
    });
  }).catch(() => undefined);
});

chrome.downloads.onCreated.addListener((item) => {
  const taskIds = recentInteraction && Date.now() - recentInteraction.timestamp < 30_000 && taskWindows.has(recentInteraction.runId)
    ? [recentInteraction.runId]
    : taskWindows.size === 1 ? [...taskWindows.keys()] : [];
  for (const runId of taskIds) {
    const key = `${runId}:${item.id}`;
    const metadata = {
      type: "download",
      phase: "started",
      downloadId: item.id,
      url: item.finalUrl || item.url,
      filename: item.filename,
      mimeType: item.mime,
      totalBytes: item.totalBytes,
    };
    downloadTasks.set(key, runId);
    downloadMetadata.set(key, metadata);
    queueTaskEvent(runId, metadata);
  }
});

chrome.downloads.onChanged.addListener((delta) => {
  for (const runId of taskWindows.keys()) {
    const key = `${runId}:${delta.id}`;
    if (!downloadTasks.has(key)) continue;
    const metadata = downloadMetadata.get(key) || {};
    const phase = delta.state?.current || (delta.error?.current ? "interrupted" : "progress");
    queueTaskEvent(runId, {
      ...metadata,
      type: "download",
      phase,
      downloadId: delta.id,
      filename: delta.filename?.current || metadata.filename,
      receivedBytes: delta.bytesReceived?.current,
      totalBytes: delta.totalBytes?.current ?? metadata.totalBytes,
      error: delta.error?.current
    });
    if (phase === "complete" || phase === "interrupted") {
      downloadTasks.delete(key);
      downloadMetadata.delete(key);
    }
  }
});

chrome.runtime.onConnect.addListener((port) => {
  if (port.name !== "popup") return;

  port.onMessage.addListener(async (message) => {
    const response = await handlePopupMessage(message);
    try {
      port.postMessage({ requestId: message?.requestId, ...response });
    } catch {
      // Popup went away.
    }
  });
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.target === "lazzy-dialog-event") {
    const runId = sender.tab ? runIdForWindow(sender.tab.windowId) : undefined;
    if (runId) queueTaskEvent(runId, {
      type: "dialog",
      tabId: sender.tab.id,
      frameId: sender.frameId,
      dialogType: message.dialogType,
      message: message.message,
      defaultValue: message.defaultValue,
      action: message.action,
    });
    return false;
  }
  if (!message || message.target !== "lazzy-service-worker") return false;

  handlePopupMessage(message)
    .then(sendResponse)
    .catch((error) => sendResponse({ ok: false, error: normalizeError(error) }));
  return true;
});

connectBridge();

function connectBridge(force = false) {
  if (force) {
    disconnectRuntimeSocket();
    disconnectNativePort();
    clearReconnectTimers();
  }

  connectRuntimeSocket();

  if (!nativeFallbackTimer) {
    nativeFallbackTimer = setTimeout(() => {
      nativeFallbackTimer = undefined;
      if (!runtimeConnected) connectNative();
    }, 2_000);
  }
}

async function connectRuntimeSocket() {
  if (runtimeSocket) return;

  const configuration = await loadRuntimeConfiguration();
  if (runtimeSocket) return;
  const runtimeURL = new URL(`ws://127.0.0.1:${configuration.port}/api/browser/native`);
  runtimeURL.searchParams.set("token", configuration.token);
  const socket = new WebSocket(runtimeURL.toString());
  runtimeSocket = socket;

  socket.addEventListener("open", () => {
    if (runtimeSocket !== socket) return;
    runtimeConnected = true;
    runtimeReconnectAttempt = 0;
    lastNativeError = undefined;

    if (nativeFallbackTimer) {
      clearTimeout(nativeFallbackTimer);
      nativeFallbackTimer = undefined;
    }

    disconnectNativePort();
    sendRuntime({
      type: "event",
      event: "extension.ready",
      payload: {
        transport: "websocket",
        version: chrome.runtime.getManifest().version
      }
    });
    startRuntimeHeartbeat();
  });

  socket.addEventListener("message", (event) => {
    if (runtimeSocket !== socket) return;
    try {
      handleNativeMessage(JSON.parse(String(event.data))).catch((error) => {
        sendBridge({ type: "event", event: "extension.error", error: normalizeError(error) });
      });
    } catch {
      lastNativeError = "Detach sent an invalid browser bridge message";
    }
  });

  socket.addEventListener("error", () => {
    if (runtimeSocket !== socket) return;
    lastNativeError = "Could not connect to the Detach runtime";
  });

  socket.addEventListener("close", () => {
    if (runtimeSocket !== socket) return;
    runtimeSocket = undefined;
    runtimeConnected = false;
    stopRuntimeHeartbeat();
    scheduleRuntimeReconnect();
  });
}

async function loadRuntimeConfiguration() {
  try {
    const response = await fetch(chrome.runtime.getURL("runtime-config.json"), { cache: "no-store" });
    if (!response.ok) return DEFAULT_RUNTIME_CONFIG;
    const value = await response.json();
    if (!Number.isInteger(value.port) || value.port < 1 || value.port > 65535) {
      return DEFAULT_RUNTIME_CONFIG;
    }
    if (typeof value.token !== "string" || value.token.length < 16) {
      return DEFAULT_RUNTIME_CONFIG;
    }
    return { port: value.port, token: value.token };
  } catch {
    return DEFAULT_RUNTIME_CONFIG;
  }
}

function scheduleRuntimeReconnect() {
  if (runtimeReconnectTimer) return;
  const delay = Math.min(1_000 * (2 ** runtimeReconnectAttempt), MAX_RECONNECT_DELAY_MS);
  runtimeReconnectAttempt += 1;
  runtimeReconnectTimer = setTimeout(() => {
    runtimeReconnectTimer = undefined;
    connectBridge();
  }, delay);
}

function startRuntimeHeartbeat() {
  stopRuntimeHeartbeat();
  runtimeHeartbeat = setInterval(() => {
    sendRuntime({ type: "event", event: "extension.heartbeat" });
  }, HEARTBEAT_INTERVAL_MS);
}

function stopRuntimeHeartbeat() {
  if (runtimeHeartbeat) clearInterval(runtimeHeartbeat);
  runtimeHeartbeat = undefined;
}

function disconnectRuntimeSocket() {
  const socket = runtimeSocket;
  runtimeSocket = undefined;
  runtimeConnected = false;
  stopRuntimeHeartbeat();
  try {
    socket?.close();
  } catch {
    // Socket was already closed.
  }
}

function connectNative() {
  if (nativePort) return;

  try {
    const port = chrome.runtime.connectNative(NATIVE_HOST);
    nativePort = port;
    nativeConnected = false;

    port.onMessage.addListener((message) => {
      if (nativePort !== port) return;
      nativeConnected = true;
      nativeReconnectAttempt = 0;
      lastNativeError = undefined;
      handleNativeMessage(message).catch((error) => {
        sendNative({
          type: "event",
          event: "extension.error",
          error: normalizeError(error)
        });
      });
    });

    port.onDisconnect.addListener(() => {
      if (nativePort !== port) return;
      nativeConnected = false;
      nativePort = undefined;
      if (!isRuntimeSocketOpen()) runtimeConnected = false;
      lastNativeError = chrome.runtime.lastError?.message || "Native host disconnected";
      scheduleNativeReconnect();
    });

    sendNative({
      type: "event",
      event: "extension.ready",
      payload: {
        host: NATIVE_HOST,
        version: chrome.runtime.getManifest().version
      }
    });
  } catch (error) {
    nativeConnected = false;
    nativePort = undefined;
    lastNativeError = normalizeError(error);
    scheduleNativeReconnect();
  }
}

function scheduleNativeReconnect() {
  if (nativeReconnectTimer || isRuntimeSocketOpen()) return;
  const delay = Math.min(1_000 * (2 ** nativeReconnectAttempt), MAX_RECONNECT_DELAY_MS);
  nativeReconnectAttempt += 1;
  nativeReconnectTimer = setTimeout(() => {
    nativeReconnectTimer = undefined;
    connectNative();
  }, delay);
}

function disconnectNativePort() {
  const port = nativePort;
  nativePort = undefined;
  nativeConnected = false;
  try {
    port?.disconnect();
  } catch {
    // Port was already disconnected.
  }
}

function clearReconnectTimers() {
  if (runtimeReconnectTimer) clearTimeout(runtimeReconnectTimer);
  if (nativeReconnectTimer) clearTimeout(nativeReconnectTimer);
  if (nativeFallbackTimer) clearTimeout(nativeFallbackTimer);
  runtimeReconnectTimer = undefined;
  nativeReconnectTimer = undefined;
  nativeFallbackTimer = undefined;
}

async function handleNativeMessage(message) {
  if (!message || typeof message !== "object") return;

  if (message.type === "event") {
    handleNativeEvent(message);
    return;
  }

  if (message.type !== "command") {
    return;
  }

  const { id, command, payload } = message;
  if (!id || typeof command !== "string") {
    sendBridge({
      type: "result",
      id,
      ok: false,
      error: "Invalid Detach browser command"
    });
    return;
  }

  try {
    if (typeof payload?.runId === "string" && [
      "browser.click", "browser.key", "browser.select", "browser.upload_file", "browser.drag"
    ].includes(command)) {
      recentInteraction = { runId: payload.runId, timestamp: Date.now() };
    }
    const result = await runBrowserCommand(command, payload || {});
    sendBridge({ type: "result", id, ok: true, result });
  } catch (error) {
    if (typeof payload?.runId === "string") {
      queueTaskEvent(payload.runId, { type: "failure", command, error: normalizeError(error) });
    }
    sendBridge({ type: "result", id, ok: false, error: normalizeError(error) });
  }
}

async function handlePopupMessage(message) {
  if (!message || typeof message !== "object") {
    return { ok: false, error: "Invalid popup message" };
  }

  switch (message.command) {
    case "status":
      return { ok: true, result: await buildStatus() };
    case "connect":
      connectBridge(true);
      await waitForConnection(750);
      return { ok: true, result: await buildStatus() };
    case "getActiveSnapshot":
      return { ok: true, result: await runBrowserCommand("browser.snapshot", {}) };
    default:
      return { ok: false, error: `Unknown popup command: ${message.command}` };
  }
}

async function runBrowserCommand(command, payload) {
  switch (command) {
    case "browser.begin_task":
      return beginTask(payload);
    case "browser.end_task":
      return endTask(payload);
    case "browser.status":
      return buildStatus(payload);
    case "browser.list_tabs":
      return listTabs(payload);
    case "browser.get_active_tab":
      return getActiveTabSummary(payload);
    case "browser.open_tab":
      return openTab(payload);
    case "browser.activate_tab":
      return activateTab(payload);
    case "browser.close_tab":
      return closeTab(payload);
    case "browser.navigate":
      return navigate(payload);
    case "browser.back":
      return goHistory(payload, "back");
    case "browser.forward":
      return goHistory(payload, "forward");
    case "browser.refresh":
      return refresh(payload);
    case "browser.frames":
      return listFrames(payload);
    case "browser.resolve_frame":
      return resolveFrame(payload);
    case "browser.snapshot":
      return snapshotAllFrames(payload);
    case "browser.extract_text":
      return extractTextAllFrames(payload);
    case "browser.query":
      return queryAllFrames(payload);
    case "browser.get_selection":
      return sendContentCommand(await resolveTabId(payload), "getSelection", payload);
    case "browser.click":
      return clickAndVerify(payload);
    case "browser.focus":
      return sendContentCommand(await resolveTabId(payload), "focus", payload);
    case "browser.check":
      return sendContentCommand(await resolveTabId(payload), "check", payload);
    case "browser.hover":
      return sendContentCommand(await resolveTabId(payload), "hover", payload);
    case "browser.drag":
      return dragAndVerify(payload);
    case "browser.type":
      return sendContentCommand(await resolveTabId(payload), "type", payload);
    case "browser.key":
      return keyAndVerify(payload);
    case "browser.prepare_secret_fill":
      return sendContentCommand(await resolveTabId(payload), "prepareSecretFill", payload);
    case "browser.secure_fill":
      return secureFillAndVerify(payload);
    case "browser.lock_sensitive_document":
      {
        const tabId = await resolveTabId(payload);
        sensitiveTabIds.add(tabId);
        return sendContentCommand(tabId, "lockSensitiveDocument", payload);
      }
    case "browser.select":
      return sendContentCommand(await resolveTabId(payload), "select", payload);
    case "browser.dropdown_options":
      return sendContentCommand(await resolveTabId(payload), "dropdownOptions", payload);
    case "browser.upload_file":
      return sendContentCommand(await resolveTabId(payload), "uploadFile", payload);
    case "browser.scroll":
      return sendContentCommand(await resolveTabId(payload), "scroll", payload);
    case "browser.wait":
      return sendContentCommand(await resolveTabId(payload), "wait", payload);
    case "browser.media":
      return sendContentCommand(await resolveTabId(payload), "media", payload);
    case "browser.artifact_fetch":
      return fetchArtifact(payload);
    case "browser.screenshot":
      {
        const tabId = await resolveTabId(payload);
        if (sensitiveTabIds.has(tabId)) throw new Error("INSPECTION_LOCKED: Navigate before capturing a screenshot after secure credential fill.");
        return captureVisibleTab({ ...payload, tabId });
      }
    case "browser.events":
      return readTaskEvents(payload);
    case "browser.dialog":
      return setDialogPolicy(payload);
    case "browser.request_all_sites_access":
      return requestAllSitesAccess();
    default:
      throw new Error(`Unsupported Detach browser command: ${command}`);
  }
}

async function buildStatus(payload = {}) {
  const activeTab = await getActiveTabSummary(payload).catch(() => undefined);
  const hasAllSites = await containsPermission({ origins: ["<all_urls>"] });

  return {
    extensionConnected: true,
    nativeConnected,
    runtimeConnected,
    transport: isRuntimeSocketOpen() ? "websocket" : nativeConnected ? "native" : "none",
    nativeHost: NATIVE_HOST,
    nativeError: lastNativeError,
    hasAllSitesAccess: hasAllSites,
    engine: "extension",
    profile: "signed_in",
    taskIsolated: false,
    activeTab
  };
}

function handleNativeEvent(message) {
  if (message.event === "runtime.connected") {
    runtimeConnected = true;
    lastNativeError = undefined;
  }

  if (message.event === "runtime.disconnected") {
    runtimeConnected = false;
    lastNativeError = "Detach runtime is not connected";
  }

  if (message.event === "runtime.error" || message.event === "native.error") {
    runtimeConnected = false;
    lastNativeError = message.error || "Browser bridge error";
  }
}

async function beginTask(payload = {}) {
  const runId = requireString(payload.runId, "runId");
  const existingWindowId = taskWindows.get(runId);
  if (Number.isInteger(existingWindowId)) {
    return { runId, windowId: existingWindowId, reused: true };
  }
  const [activeTab] = await tabsQuery({ active: true, lastFocusedWindow: true });
  if (!Number.isInteger(activeTab?.windowId)) throw new Error("Chrome has no focused normal window to reuse");
  taskWindows.set(runId, activeTab.windowId);
  taskEvents.set(runId, []);
  await ensureContentScripts(activeTab.id).catch(() => undefined);
  return { runId, windowId: activeTab.windowId, tabId: activeTab.id, reused: true };
}

async function endTask(payload = {}) {
  const runId = requireString(payload.runId, "runId");
  const windowId = taskWindows.get(runId);
  taskWindows.delete(runId);
  taskEvents.delete(runId);
  for (const key of downloadTasks.keys()) {
    if (!key.startsWith(`${runId}:`)) continue;
    downloadTasks.delete(key);
    downloadMetadata.delete(key);
  }
  if (Number.isInteger(windowId)) {
    const tabs = await tabsQuery({ windowId }).catch(() => []);
    for (const tab of tabs) clearTabRefs(tab.id);
  }
  return { runId, closed: false, reusedWindow: true };
}

async function listTabs(payload = {}) {
  const windowId = resolveTaskWindowId(payload);
  const tabs = await tabsQuery(Number.isInteger(windowId) ? { windowId } : {});
  return tabs.map(summarizeTab);
}

async function getActiveTabSummary(payload = {}) {
  return summarizeTab(await getActiveTab(payload));
}

async function getActiveTab(payload = {}) {
  const windowId = resolveTaskWindowId(payload);
  const [tab] = await tabsQuery(Number.isInteger(windowId)
    ? { active: true, windowId }
    : { active: true, currentWindow: true });
  if (!tab?.id) {
    throw new Error("No active Chrome tab found");
  }
  return tab;
}

async function resolveTabId(payload = {}) {
  if (Number.isInteger(payload.tabId)) return payload.tabId;
  return (await getActiveTab(payload)).id;
}

async function navigate(payload = {}) {
  const tabId = await resolveTabId(payload);
  const url = requireWebUrl(payload.url);
  sensitiveTabIds.delete(tabId);
  await tabsUpdate(tabId, { url });
  return summarizeTab(await waitForTabReady(tabId, payload.timeoutMs));
}

async function openTab(payload = {}) {
  const url = requireWebUrl(payload.url);
  const windowId = resolveTaskWindowId(payload);
  if (Number.isInteger(windowId)) {
    const existingTabs = await tabsQuery({ windowId });
    const reusable = existingTabs.length === 1 && (existingTabs[0].url === "about:blank" || existingTabs[0].url === "chrome://newtab/")
      ? existingTabs[0]
      : undefined;
    if (reusable?.id) {
      await tabsUpdate(reusable.id, { url, active: payload.active !== false });
      return summarizeTab(await waitForTabReady(reusable.id, payload.timeoutMs));
    }
  }
  const tab = await tabsCreate({
    url,
    active: payload.active !== false,
    ...(Number.isInteger(windowId) ? { windowId } : {})
  });
  return summarizeTab(await waitForTabReady(tab.id, payload.timeoutMs));
}

async function activateTab(payload = {}) {
  const tabId = await resolveTabId(payload);
  const tab = await tabsUpdate(tabId, { active: true });
  await windowsUpdate(tab.windowId, { focused: true });
  return summarizeTab(tab);
}

async function closeTab(payload = {}) {
  const tabId = await resolveTabId(payload);
  const windowId = resolveTaskWindowId(payload);
  if (Number.isInteger(windowId)) {
    const tabs = await tabsQuery({ windowId });
    if (tabs.length <= 1) throw new Error("Cannot close the only tab in this browser task");
  }
  await tabsRemove(tabId);
  return { closed: tabId, activeTab: await getActiveTabSummary(payload).catch(() => undefined) };
}

async function goHistory(payload = {}, direction) {
  const tabId = await resolveTabId(payload);
  if (direction === "back") await tabsGoBack(tabId);
  else await tabsGoForward(tabId);
  return summarizeTab(await waitForTabReady(tabId, payload.timeoutMs));
}

async function refresh(payload = {}) {
  const tabId = await resolveTabId(payload);
  await tabsReload(tabId, { bypassCache: Boolean(payload.ignoreCache) });
  return summarizeTab(await waitForTabReady(tabId, payload.timeoutMs));
}

async function captureVisibleTab(payload = {}) {
  let tab = Number.isInteger(payload.tabId) ? await tabsGet(payload.tabId) : await getActiveTab(payload);
  if (!tab.active) {
    tab = await tabsUpdate(tab.id, { active: true });
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  const format = payload.format === "jpeg" ? "jpeg" : "png";
  const quality = typeof payload.quality === "number" ? payload.quality : undefined;
  let dataUrl = await tabsCaptureVisibleTab(tab.windowId, { format, quality });
  let croppedDataUrl;
  let crop;
  if (payload.ref || payload.selector || payload.targetText || payload.role || payload.label) {
    let elementResult = await queryAllFrames({ ...payload, tabId: tab.id, kind: "element" });
    let element = elementResult.element;
    if (!element?.rect) throw new Error("The screenshot target has no visible rectangle");
    await sendContentCommand(tab.id, "scroll", {
      ref: element.ref,
      frameId: element.frameId,
      documentId: element.documentId,
      block: "center",
    });
    await new Promise((resolve) => setTimeout(resolve, 50));
    dataUrl = await tabsCaptureVisibleTab(tab.windowId, { format, quality });
    elementResult = await queryAllFrames({
      ref: element.ref,
      frameId: element.frameId,
      documentId: element.documentId,
      tabId: tab.id,
      kind: "element",
    });
    element = elementResult.element;
    crop = await absoluteElementRect(tab.id, element);
    croppedDataUrl = await cropImageDataUrl(dataUrl, crop);
  }

  return {
    tab: summarizeTab(tab),
    format,
    dataUrl: croppedDataUrl || dataUrl,
    cropped: Boolean(croppedDataUrl),
    crop,
  };
}

async function clickAndVerify(payload = {}) {
  return actionAndVerify(payload, "click");
}

async function keyAndVerify(payload = {}) {
  return actionAndVerify(payload, "key");
}

async function dragAndVerify(payload = {}) {
  return actionAndVerify(payload, "drag");
}

async function secureFillAndVerify(payload = {}) {
  const tabId = await resolveTabId(payload);
  const before = await tabsGet(tabId);
  const beforeRevision = navigationRevisions.get(tabId) || 0;
  sensitiveTabIds.add(tabId);
  let fillResult;
  try {
    fillResult = await sendContentCommand(tabId, "secureFill", payload);
  } catch (error) {
    const message = normalizeError(error);
    if (!payload.submitRef || !/message port closed|receiving end does not exist|context invalidated|frame was removed/i.test(message)) throw error;
    fillResult = { filled: true, submitted: true, navigationInterruptedResponse: true };
  }

  const submitted = fillResult?.submitted === true || Boolean(payload.submitRef);
  const after = submitted ? await settleAfterAction(tabId, before, payload.timeoutMs || 12_000, beforeRevision) : await tabsGet(tabId);
  const navigationChanged = Boolean(after.url && after.url !== before.url);
  const documentReloaded = Boolean(after.detachSawNavigation);
  if (navigationChanged) {
    sensitiveTabIds.delete(tabId);
    await ensureContentScript(tabId).catch(() => undefined);
    await sendContentCommand(tabId, "unlockSensitiveDocument", {}).catch(() => undefined);
  } else if (documentReloaded) {
    await ensureContentScript(tabId).catch(() => undefined);
    await sendContentCommand(tabId, "lockSensitiveDocument", {}).catch(() => undefined);
  }

  return {
    filled: fillResult?.filled !== false,
    submitted,
    inspection: navigationChanged ? "unlocked_after_navigation" : "locked_until_navigation",
    navigation: {
      changed: navigationChanged,
      documentReloaded,
      beforeUrl: before.url || "",
      afterUrl: after.url || "",
      title: after.title || "",
      status: after.status || "unknown"
    },
    next: navigationChanged ? "verify_new_document" : submitted ? "site_remained_on_login_page" : "submit_required"
  };
}

async function actionAndVerify(payload, command) {
  const tabId = await resolveTabId(payload);
  const before = await tabsGet(tabId);
  const beforeRevision = navigationRevisions.get(tabId) || 0;
  const actionStartedAt = Date.now();
  let actionResult;
  try {
    actionResult = await sendContentCommand(tabId, command, payload);
  } catch (error) {
    const message = normalizeError(error);
    if (!/message port closed|receiving end does not exist|context invalidated|frame was removed/i.test(message)) throw error;
    actionResult = { dispatched: true, navigationInterruptedResponse: true };
  }
  const after = await settleAfterAction(tabId, before, payload.timeoutMs, beforeRevision);
  return {
    ...actionResult,
    before: summarizeTab(before),
    after: summarizeTab(after),
    events: taskEventsSince(payload.runId, actionStartedAt),
    verified: true
  };
}

async function settleAfterAction(tabId, before, requestedTimeout, beforeRevision = navigationRevisions.get(tabId) || 0) {
  const timeoutMs = Math.max(500, Math.min(15_000, Number(requestedTimeout) || 5_000));
  const startedAt = Date.now();
  let sawNavigation = false;
  let tab = before;
  while (Date.now() - startedAt < timeoutMs) {
    tab = await tabsGet(tabId);
    sawNavigation ||= tab.status === "loading"
      || tab.url !== before.url
      || (navigationRevisions.get(tabId) || 0) > beforeRevision;
    if (sawNavigation && tab.status === "complete") {
      if (/^https?:\/\//.test(tab.url || "")) {
        await ensureContentScript(tabId).catch(() => undefined);
        await sendContentCommand(tabId, "wait", { timeoutMs: Math.min(4_000, timeoutMs) }).catch(() => undefined);
      }
      return { ...(await tabsGet(tabId)), detachSawNavigation: true };
    }
    if (!sawNavigation && Date.now() - startedAt >= 400) return { ...tab, detachSawNavigation: false };
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  return { ...tab, detachSawNavigation: sawNavigation };
}

async function waitForTabReady(tabId, requestedTimeout) {
  const timeoutMs = Math.max(500, Math.min(60_000, Number(requestedTimeout) || 15_000));
  const startedAt = Date.now();
  const deadline = Date.now() + timeoutMs;
  let lastTab;
  let lastSoftReadyAttempt = 0;
  while (Date.now() < deadline) {
    lastTab = await tabsGet(tabId);
    if (lastTab.status === "complete") {
      if (/^https?:\/\//.test(lastTab.url || "")) {
        await ensureContentScript(tabId).catch(() => undefined);
        await sendContentCommand(tabId, "wait", { timeoutMs: Math.min(5_000, timeoutMs) }).catch(() => undefined);
      }
      return await tabsGet(tabId);
    }
    if (
      /^https?:\/\//.test(lastTab.url || "")
      && Date.now() - startedAt >= 1_000
      && Date.now() - lastSoftReadyAttempt >= 750
    ) {
      lastSoftReadyAttempt = Date.now();
      try {
        await ensureContentScript(tabId);
        const state = await sendContentCommand(tabId, "wait", { timeoutMs: 700 });
        if (state?.matched) return { ...(await tabsGet(tabId)), detachSoftReady: true };
      } catch {
        // The document may still be replacing its execution context; keep polling.
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (/^https?:\/\//.test(lastTab?.url || "")) {
    try {
      await ensureContentScript(tabId);
      const body = await sendContentCommand(tabId, "query", { selector: "body", kind: "count" });
      if (body?.count > 0) return { ...(await tabsGet(tabId)), detachSoftReady: true, detachLoadTimedOut: true };
    } catch {
      // A page with no inspectable document remains a real navigation failure.
    }
  }
  throw new Error(`NAVIGATION_TIMEOUT: Browser tab did not finish loading within ${timeoutMs}ms (${lastTab?.url || "unknown URL"})`);
}

async function listFrames(payload = {}) {
  const tabId = await resolveTabId(payload);
  await ensureSupportedTab(tabId);
  await ensureContentScripts(tabId);
  const frames = await webNavigationGetAllFrames({ tabId });
  return {
    tabId,
    frames: frames.map((frame) => ({
      frameId: frame.frameId,
      parentFrameId: frame.parentFrameId,
      documentId: frame.documentId,
      documentLifecycle: frame.documentLifecycle,
      url: frame.url,
      main: frame.frameId === 0,
    })),
  };
}

async function snapshotAllFrames(payload = {}) {
  const tabId = await resolveTabId(payload);
  const framesResult = await listFrames({ ...payload, tabId });
  const frameSnapshots = await collectFrameResults(tabId, framesResult.frames, "snapshot", payload);
  if (frameSnapshots.length === 0) throw new Error("No inspectable browser frame was found");
  const main = frameSnapshots.find((entry) => entry.frame.frameId === 0) || frameSnapshots[0];
  const maxElements = Math.max(1, Math.min(500, Number(payload.maxElements) || 180));
  const elements = [];
  const tables = [];
  const textParts = [];
  const changed = [];
  const removedRefs = [];
  let unchangedCount = 0;
  for (const { frame, result } of frameSnapshots) {
    registerFrameRefs(tabId, frame, result);
    const frameElements = Array.isArray(result.elements)
      ? result.elements.map((element) => withFrame(element, frame))
      : [];
    elements.push(...frameElements);
    if (typeof result.text === "string" && result.text.trim()) {
      textParts.push(frame.frameId === 0 ? result.text : `[Frame ${frame.frameId}: ${frame.url}]\n${result.text}`);
    }
    if (Array.isArray(result.tables)) {
      tables.push(...result.tables.map((table) => ({ ...table, frameId: frame.frameId, frameUrl: frame.url })));
    }
    const delta = result.delta || {};
    if (Array.isArray(delta.changed)) changed.push(...delta.changed.map((element) => withFrame(element, frame)));
    if (Array.isArray(delta.removedRefs)) removedRefs.push(...delta.removedRefs);
    unchangedCount += Number(delta.unchangedCount) || 0;
  }
  return {
    ...main.result,
    engine: "extension",
    url: main.result.url,
    title: main.result.title,
    frames: framesResult.frames,
    text: textParts.join("\n\n").slice(0, Math.max(1_000, Math.min(80_000, Number(payload.maxTextLength) || 12_000))),
    elements: elements.slice(0, maxElements),
    tables: tables.slice(0, 20),
    delta: {
      changed: changed.slice(0, maxElements),
      removedRefs: removedRefs.slice(0, maxElements),
      unchangedCount,
    },
  };
}

async function extractTextAllFrames(payload = {}) {
  const tabId = await resolveTabId(payload);
  if (Number.isInteger(payload.frameId) || payload.ref) {
    return await sendContentCommand(tabId, "extractText", payload);
  }
  const framesResult = await listFrames({ ...payload, tabId });
  const results = await collectFrameResults(tabId, framesResult.frames, "extractText", payload);
  const maxLength = Math.max(1_000, Math.min(80_000, Number(payload.maxLength) || 20_000));
  const text = results.map(({ frame, result }) => {
    const value = typeof result.text === "string" ? result.text : "";
    return frame.frameId === 0 ? value : `[Frame ${frame.frameId}: ${frame.url}]\n${value}`;
  }).filter(Boolean).join("\n\n");
  return { text: text.slice(0, maxLength), truncated: text.length > maxLength, frames: results.length };
}

async function queryAllFrames(payload = {}) {
  const tabId = await resolveTabId(payload);
  const targetedFrame = await targetFrameForPayload(tabId, payload, false);
  if (targetedFrame) {
    const result = await sendFrameCommand(tabId, targetedFrame, "query", payload);
    registerQueryRefs(tabId, targetedFrame, result);
    return addFrameToQueryResult(result, targetedFrame);
  }

  const framesResult = await listFrames({ ...payload, tabId });
  const results = await collectFrameResults(tabId, framesResult.frames, "query", payload);
  for (const entry of results) registerQueryRefs(tabId, entry.frame, entry.result);
  const kind = String(payload.kind || "all");
  if (kind === "count") return { count: results.reduce((sum, entry) => sum + (Number(entry.result.count) || 0), 0) };
  if (kind === "all") {
    const elements = results.flatMap(({ frame, result }) => Array.isArray(result.elements)
      ? result.elements.map((element) => withFrame(element, frame))
      : []);
    return { count: elements.length, elements: elements.slice(0, Number(payload.maxResults) || 250) };
  }
  const match = results.find((entry) => entry.result?.matched !== false && (
    "value" in (entry.result || {}) || entry.result?.element || entry.result?.valid !== undefined
  ));
  if (!match) {
    if (kind === "textContent" || kind === "innerText") return { value: null, matched: false };
    throw new Error(`No page element matched the live ${kind} query in any frame`);
  }
  return addFrameToQueryResult(match.result, match.frame);
}

async function resolveFrame(payload = {}) {
  const tabId = await resolveTabId(payload);
  if (Number.isInteger(payload.frameId)) {
    const frame = (await listFrames({ tabId })).frames.find((candidate) => candidate.frameId === payload.frameId);
    if (!frame) throw new Error(`No browser frame found: ${payload.frameId}`);
    return frame;
  }
  const selector = requireString(payload.selector, "selector");
  const frames = (await listFrames({ tabId })).frames;
  const candidates = [];
  for (const parent of frames) {
    try {
      const result = await sendFrameCommand(tabId, parent, "query", { selector, kind: "all", maxResults: 20 });
      for (const element of result.elements || []) {
        if (String(element.tagName || "").toLowerCase() !== "iframe") continue;
        const src = element.attributes?.src || element.src || "";
        const child = frames.find((frame) => frame.parentFrameId === parent.frameId && urlsEquivalent(frame.url, src, parent.url));
        if (child) candidates.push({ ...child, owner: withFrame(element, parent) });
      }
    } catch {
      // This parent frame may not be inspectable.
    }
  }
  if (candidates.length === 0) throw new Error(`No iframe matched selector: ${selector}`);
  if (candidates.length > 1) throw new Error(`Frame selector matched ${candidates.length} iframes; use a more specific selector`);
  return candidates[0];
}

async function collectFrameResults(tabId, frames, command, payload) {
  const results = [];
  for (const frame of frames) {
    try {
      const result = await sendFrameCommand(tabId, frame, command, payload);
      results.push({ frame, result });
    } catch {
      // Chrome may deny injection in a restricted child origin. Other frames remain useful.
    }
  }
  return results;
}

function registerFrameRefs(tabId, frame, result) {
  for (const element of result.elements || []) registerRef(tabId, frame, element.ref);
  for (const element of result.delta?.changed || []) registerRef(tabId, frame, element.ref);
}

function registerQueryRefs(tabId, frame, result) {
  if (result.element?.ref) registerRef(tabId, frame, result.element.ref);
  for (const element of result.elements || []) registerRef(tabId, frame, element.ref);
}

function registerRef(tabId, frame, ref) {
  if (!ref) return;
  refTargets.set(`${tabId}:${ref}`, {
    frameId: frame.frameId,
    documentId: frame.documentId,
    frameUrl: frame.url,
  });
}

function clearTabRefs(tabId) {
  for (const key of refTargets.keys()) {
    if (key.startsWith(`${tabId}:`)) refTargets.delete(key);
  }
  activeFrameByTab.delete(tabId);
}

function withFrame(element, frame) {
  return {
    ...element,
    frameId: frame.frameId,
    documentId: frame.documentId,
    frameUrl: frame.url,
  };
}

function addFrameToQueryResult(result, frame) {
  return {
    ...result,
    frameId: frame.frameId,
    documentId: frame.documentId,
    frameUrl: frame.url,
    ...(result.element ? { element: withFrame(result.element, frame) } : {}),
    ...(Array.isArray(result.elements) ? { elements: result.elements.map((element) => withFrame(element, frame)) } : {}),
  };
}

async function targetFrameForPayload(tabId, payload, discover = true) {
  const frames = (await listFrames({ tabId })).frames;
  if (Number.isInteger(payload.frameId)) {
    const frame = frames.find((candidate) => candidate.frameId === payload.frameId);
    if (!frame) throw new Error(`Browser frame is stale or missing: ${payload.frameId}`);
    if (payload.documentId && frame.documentId && payload.documentId !== frame.documentId) {
      throw new Error("STALE_REF: Browser frame navigated. Take a new snapshot.");
    }
    return frame;
  }
  if (payload.ref) {
    const stored = refTargets.get(`${tabId}:${payload.ref}`);
    if (!stored) throw new Error(`STALE_REF: Browser ref has no live frame: ${payload.ref}. Take a new snapshot.`);
    const frame = frames.find((candidate) => candidate.frameId === stored.frameId);
    if (!frame || (stored.documentId && frame.documentId && stored.documentId !== frame.documentId)) {
      refTargets.delete(`${tabId}:${payload.ref}`);
      throw new Error(`STALE_REF: Browser ref belongs to an earlier document: ${payload.ref}. Take a new snapshot.`);
    }
    return frame;
  }
  if (!discover) return undefined;
  if (!payload.selector && !payload.targetText && !payload.text && !payload.role && !payload.label) {
    return frames.find((candidate) => candidate.frameId === activeFrameByTab.get(tabId))
      || frames.find((candidate) => candidate.frameId === 0);
  }
  const matching = [];
  for (const frame of frames) {
    try {
      const result = await sendFrameCommand(tabId, frame, "query", { ...payload, kind: "count" });
      if ((Number(result.count) || 0) > 0) matching.push(frame);
    } catch {
      // Ignore inaccessible frames.
    }
  }
  if (matching.length === 0) throw new Error("No page element matched in any browser frame");
  if (matching.length > 1) throw new Error(`Target matched elements in ${matching.length} frames; use frameLocator() or a stable ref`);
  return matching[0];
}

async function fetchArtifact(payload = {}) {
  const tabId = await resolveTabId(payload);
  try {
    return await sendContentCommand(tabId, "fetchArtifact", payload);
  } catch (contentError) {
    const url = typeof payload.url === "string" ? payload.url : "";
    if (!/^https?:\/\//.test(url)) throw contentError;
    const response = await fetch(url, { credentials: "include" });
    if (!response.ok) throw new Error(`Document fetch failed with HTTP ${response.status}`);
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.byteLength > 25 * 1024 * 1024) throw new Error("Document is larger than 25 MB");
    return {
      url: response.url || url,
      mimeType: response.headers.get("content-type") || "application/octet-stream",
      fileName: fileNameFromResponse(response, url),
      dataBase64: bytesToBase64(bytes),
    };
  }
}

async function setDialogPolicy(payload = {}) {
  const tabId = await resolveTabId(payload);
  const frame = await targetFrameForPayload(tabId, payload);
  const action = payload.action === "dismiss" ? "dismiss" : "accept";
  const promptText = typeof payload.promptText === "string" ? payload.promptText : "";
  await scriptingExecuteScript({
    target: { tabId, frameIds: [frame.frameId] },
    world: "MAIN",
    func: (policy) => {
      const state = window.__detachDialogState || { installed: false };
      state.action = policy.action;
      state.promptText = policy.promptText;
      if (!state.installed) {
        const notify = (dialogType, message, defaultValue, resultAction) => {
          window.postMessage({
            source: "detach-dialog-bridge",
            dialogType,
            message: String(message || ""),
            defaultValue: String(defaultValue || ""),
            action: resultAction,
          }, "*");
        };
        window.alert = (message) => notify("alert", message, "", "accept");
        window.confirm = (message) => {
          const accepted = state.action !== "dismiss";
          notify("confirm", message, "", accepted ? "accept" : "dismiss");
          return accepted;
        };
        window.prompt = (message, defaultValue = "") => {
          const accepted = state.action !== "dismiss";
          notify("prompt", message, defaultValue, accepted ? "accept" : "dismiss");
          return accepted ? state.promptText || String(defaultValue || "") : null;
        };
        state.installed = true;
      }
      window.__detachDialogState = state;
      return { installed: true, action: state.action };
    },
    args: [{ action, promptText }],
  });
  return { installed: true, action, frameId: frame.frameId, appliesTo: "next_and_future_page_dialogs_in_document" };
}

function recordNavigation(details, phase) {
  if (phase === "committed") {
    navigationRevisions.set(details.tabId, (navigationRevisions.get(details.tabId) || 0) + 1);
    if (details.frameId === 0) clearTabRefs(details.tabId);
  }
  tabsGet(details.tabId).then((tab) => {
    const runId = runIdForWindow(tab.windowId);
    if (!runId) return;
    queueTaskEvent(runId, {
      type: "navigation",
      phase,
      tabId: details.tabId,
      frameId: details.frameId,
      parentFrameId: details.parentFrameId,
      documentId: details.documentId,
      documentLifecycle: details.documentLifecycle,
      url: details.url,
      transitionType: details.transitionType,
      transitionQualifiers: details.transitionQualifiers,
      error: details.error,
    });
  }).catch(() => undefined);
}

function taskEventsSince(runId, timestamp) {
  if (typeof runId !== "string") return [];
  return (taskEvents.get(runId) || []).filter((event) => event.timestamp >= timestamp).slice(-20);
}

async function absoluteElementRect(tabId, element) {
  let x = Number(element.rect.x) || 0;
  let y = Number(element.rect.y) || 0;
  const width = Math.max(1, Number(element.rect.width) || 1);
  const height = Math.max(1, Number(element.rect.height) || 1);
  let frameId = Number(element.frameId) || 0;
  const frames = (await listFrames({ tabId })).frames;
  const seen = new Set();
  while (frameId !== 0 && !seen.has(frameId)) {
    seen.add(frameId);
    const frame = frames.find((candidate) => candidate.frameId === frameId);
    if (!frame) break;
    const parent = frames.find((candidate) => candidate.frameId === frame.parentFrameId);
    if (!parent) break;
    const owner = await findFrameOwner(tabId, parent, frame);
    if (!owner?.rect) break;
    x += Number(owner.rect.x) || 0;
    y += Number(owner.rect.y) || 0;
    frameId = parent.frameId;
  }
  const mainViewport = await sendFrameCommand(
    tabId,
    frames.find((candidate) => candidate.frameId === 0) || frames[0],
    "query",
    { selector: "html", kind: "element" }
  ).catch(() => ({}));
  const devicePixelRatio = Number(mainViewport.element?.devicePixelRatio || element.devicePixelRatio) || 1;
  return { x, y, width, height, devicePixelRatio };
}

async function findFrameOwner(tabId, parent, child) {
  const result = await sendFrameCommand(tabId, parent, "query", { selector: "iframe,frame", kind: "all", maxResults: 100 });
  const candidates = result.elements || [];
  const exact = candidates.find((element) => urlsEquivalent(child.url, element.attributes?.src || element.src || "", parent.url));
  if (exact) return exact;
  if (candidates.length === 1) return candidates[0];
  throw new Error(`Could not map frame ${child.frameId} to a unique iframe element for screenshot cropping`);
}

async function cropImageDataUrl(dataUrl, crop) {
  await ensureOffscreenDocument();
  const response = await runtimeSendMessage({
    target: "lazzy-offscreen",
    command: "crop",
    dataUrl,
    crop,
  });
  if (!response?.ok || !response.dataUrl) throw new Error(response?.error || "Could not crop browser screenshot");
  return response.dataUrl;
}

async function ensureOffscreenDocument() {
  const offscreenUrl = chrome.runtime.getURL("offscreen.html");
  const contexts = await runtimeGetContexts({
    contextTypes: ["OFFSCREEN_DOCUMENT"],
    documentUrls: [offscreenUrl],
  }).catch(() => []);
  if (contexts.length > 0) return;
  if (!creatingOffscreenDocument) {
    creatingOffscreenDocument = chrome.offscreen.createDocument({
      url: "offscreen.html",
      reasons: ["BLOBS", "DOM_PARSER"],
      justification: "Crop browser screenshots and inspect task-owned document blobs",
    }).finally(() => {
      creatingOffscreenDocument = undefined;
    });
  }
  await creatingOffscreenDocument;
}

function fileNameFromResponse(response, fallbackUrl) {
  const disposition = response.headers.get("content-disposition") || "";
  const encoded = disposition.match(/filename\*=UTF-8''([^;]+)/i)?.[1];
  const plain = disposition.match(/filename="?([^";]+)"?/i)?.[1];
  if (encoded) {
    try { return decodeURIComponent(encoded); } catch {}
  }
  if (plain) return plain;
  try {
    return decodeURIComponent(new URL(response.url || fallbackUrl).pathname.split("/").pop() || "document");
  } catch {
    return "document";
  }
}

function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, Math.min(bytes.length, offset + chunkSize)));
  }
  return btoa(binary);
}

function urlsEquivalent(actual, candidate, parentUrl) {
  if (!candidate) return false;
  try {
    return new URL(actual).href === new URL(candidate, parentUrl).href;
  } catch {
    return actual === candidate;
  }
}

function resolveTaskWindowId(payload = {}) {
  const runId = typeof payload.runId === "string" ? payload.runId : "";
  return runId ? taskWindows.get(runId) : undefined;
}

function readTaskEvents(payload = {}) {
  const runId = requireString(payload.runId, "runId");
  const events = (taskEvents.get(runId) || []).map((event) => ({ ...event }));
  if (payload.drain !== false) taskEvents.set(runId, []);
  return { events };
}

function runIdForWindow(windowId) {
  for (const [runId, taskWindowId] of taskWindows) {
    if (taskWindowId === windowId) return runId;
  }
  return undefined;
}

function queueTaskEvent(runId, event) {
  if (!taskEvents.has(runId)) taskEvents.set(runId, []);
  const events = taskEvents.get(runId);
  const queued = { ...event, timestamp: Date.now() };
  const previous = events.at(-1);
  const duplicateNavigation = queued.type === "navigation"
    && previous?.type === "navigation"
    && previous.tabId === queued.tabId
    && previous.url === queued.url
    && previous.status === queued.status;
  const replaceDownloadProgress = queued.type === "download"
    && queued.phase === "progress"
    && previous?.type === "download"
    && previous.phase === "progress"
    && previous.downloadId === queued.downloadId;
  if (replaceDownloadProgress) events[events.length - 1] = queued;
  else if (!duplicateNavigation) events.push(queued);
  if (events.length > 100) events.splice(0, events.length - 100);
}

async function requestAllSitesAccess() {
  const granted = await permissionsRequest({ origins: ["<all_urls>"] });
  return {
    granted,
    hasAllSitesAccess: await containsPermission({ origins: ["<all_urls>"] })
  };
}

async function sendContentCommand(tabId, command, payload) {
  await ensureSupportedTab(tabId);
  await ensureContentScripts(tabId);
  const frame = await targetFrameForPayload(tabId, payload);
  activeFrameByTab.set(tabId, frame.frameId);
  return sendFrameCommand(tabId, frame, command, payload);
}

async function sendFrameCommand(tabId, frame, command, payload) {
  const result = await sendMessageToTab(tabId, {
    target: CONTENT_TARGET,
    command,
    payload
  }, COMMAND_TIMEOUT_MS, frame.frameId);
  registerQueryRefs(tabId, frame, result || {});
  return result;
}

async function ensureSupportedTab(tabId) {
  const tab = await tabsGet(tabId);
  const url = tab.url || "";

  if (!/^https?:\/\//.test(url)) {
    throw new Error(
      `The browser bridge is connected, but Chrome does not allow automation on its internal page "${tab.title || url}" (${url}). ` +
      "Use browser.open_tab with an http/https URL or choose a normal tab from browser.list_tabs. No approval prompt is required."
    );
  }
}

async function ensureContentScript(tabId) {
  await ensureContentScripts(tabId);
}

async function ensureContentScripts(tabId) {
  await ensureSupportedTab(tabId);
  try {
    await scriptingExecuteScript({
      target: { tabId, allFrames: true },
      files: ["content-script.js"]
    });
  } catch {
    // Existing scripts can still respond even when one restricted frame rejects injection.
  }
  const frames = await webNavigationGetAllFrames({ tabId }).catch(() => [{ frameId: 0, parentFrameId: -1, url: "" }]);
  const responsive = [];
  for (const frame of frames) {
    try {
      await sendMessageToTab(tabId, {
        target: CONTENT_TARGET,
        command: "ping",
        payload: {}
      }, 1_000, frame.frameId);
      responsive.push(frame);
    } catch {
      // The extension has no host access to this frame.
    }
  }
  if (responsive.length === 0) throw new Error("The Detach extension cannot inspect this page. Grant site access and retry.");
  return responsive;
}

function sendMessageToTab(tabId, message, timeoutMs = COMMAND_TIMEOUT_MS, frameId) {
  const requestId = crypto.randomUUID();
  const payload = { ...message, requestId };

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      pendingCommands.delete(requestId);
      reject(new Error(`Browser command timed out: ${message.command}`));
    }, timeoutMs);

    pendingCommands.set(requestId, { resolve, reject, timeout });

    const callback = (response) => {
      const pending = pendingCommands.get(requestId);
      if (!pending) return;

      pendingCommands.delete(requestId);
      clearTimeout(pending.timeout);

      const runtimeError = chrome.runtime.lastError?.message;
      if (runtimeError) {
        pending.reject(new Error(runtimeError));
        return;
      }

      if (!response?.ok) {
        pending.reject(new Error(response?.error || "Browser command failed"));
        return;
      }

      pending.resolve(response.result);
    };
    if (Number.isInteger(frameId)) chrome.tabs.sendMessage(tabId, payload, { frameId }, callback);
    else chrome.tabs.sendMessage(tabId, payload, callback);
  });
}

function sendNative(message) {
  if (!nativePort) return false;

  try {
    nativePort.postMessage(message);
    return true;
  } catch (error) {
    nativeConnected = false;
    lastNativeError = normalizeError(error);
    return false;
  }
}

function sendRuntime(message) {
  if (!isRuntimeSocketOpen()) return false;

  try {
    runtimeSocket.send(JSON.stringify(message));
    return true;
  } catch (error) {
    runtimeConnected = false;
    lastNativeError = normalizeError(error);
    return false;
  }
}

function sendBridge(message) {
  return sendRuntime(message) || sendNative(message);
}

function isRuntimeSocketOpen() {
  return runtimeSocket?.readyState === WebSocket.OPEN;
}

function waitForConnection(timeoutMs) {
  if (runtimeConnected) return Promise.resolve();
  return new Promise((resolve) => setTimeout(resolve, timeoutMs));
}

function summarizeTab(tab) {
  if (!tab) return undefined;

  const url = tab.url || "";
  const automatable = /^https?:\/\//.test(url);

  return {
    id: tab.id,
    windowId: tab.windowId,
    active: Boolean(tab.active),
    title: tab.title || "",
    url,
    favIconUrl: tab.favIconUrl || "",
    status: tab.status || "unknown",
    softReady: Boolean(tab.detachSoftReady),
    loadTimedOut: Boolean(tab.detachLoadTimedOut),
    automatable,
    restrictionReason: automatable ? undefined : "Chrome internal pages cannot be automated by extensions"
  };
}

function requireString(value, name) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`Missing required browser command field: ${name}`);
  }
  return value.trim();
}

function requireWebUrl(value) {
  const url = requireString(value, "url");
  if (!/^https?:\/\//.test(url)) {
    throw new Error("Browser URLs must start with http:// or https://");
  }
  return url;
}

function normalizeError(error) {
  if (error instanceof Error) return error.message;
  return String(error || "Unknown error");
}

function tabsQuery(queryInfo) {
  return new Promise((resolve, reject) => {
    chrome.tabs.query(queryInfo, withLastError(resolve, reject));
  });
}

function tabsGet(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabs.get(tabId, withLastError(resolve, reject));
  });
}

function tabsUpdate(tabId, updateProperties) {
  return new Promise((resolve, reject) => {
    chrome.tabs.update(tabId, updateProperties, withLastError(resolve, reject));
  });
}

function tabsCreate(createProperties) {
  return new Promise((resolve, reject) => {
    chrome.tabs.create(createProperties, withLastError(resolve, reject));
  });
}

function tabsRemove(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabs.remove(tabId, withLastError(resolve, reject));
  });
}

function tabsGoBack(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabs.goBack(tabId, withLastError(resolve, reject));
  });
}

function tabsGoForward(tabId) {
  return new Promise((resolve, reject) => {
    chrome.tabs.goForward(tabId, withLastError(resolve, reject));
  });
}

function tabsReload(tabId, reloadProperties) {
  return new Promise((resolve, reject) => {
    chrome.tabs.reload(tabId, reloadProperties, withLastError(resolve, reject));
  });
}

function tabsCaptureVisibleTab(windowId, options) {
  return new Promise((resolve, reject) => {
    chrome.tabs.captureVisibleTab(windowId, options, withLastError(resolve, reject));
  });
}

function windowsUpdate(windowId, updateInfo) {
  return new Promise((resolve, reject) => {
    chrome.windows.update(windowId, updateInfo, withLastError(resolve, reject));
  });
}

function scriptingExecuteScript(injection) {
  return new Promise((resolve, reject) => {
    chrome.scripting.executeScript(injection, withLastError(resolve, reject));
  });
}

function permissionsRequest(permissions) {
  return new Promise((resolve, reject) => {
    chrome.permissions.request(permissions, withLastError(resolve, reject));
  });
}

function containsPermission(permissions) {
  return new Promise((resolve, reject) => {
    chrome.permissions.contains(permissions, withLastError(resolve, reject));
  });
}

function webNavigationGetAllFrames(details) {
  return new Promise((resolve, reject) => {
    chrome.webNavigation.getAllFrames(details, withLastError((frames) => resolve(frames || []), reject));
  });
}

function runtimeGetContexts(filter) {
  return chrome.runtime.getContexts(filter);
}

function runtimeSendMessage(message) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(message, withLastError(resolve, reject));
  });
}

function withLastError(resolve, reject) {
  return (result) => {
    const error = chrome.runtime.lastError?.message;
    if (error) {
      reject(new Error(error));
      return;
    }
    resolve(result);
  };
}
